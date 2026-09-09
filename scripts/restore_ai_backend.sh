#!/bin/bash
#
# Brings the Ask AI backend back after a billing outage, and leaves it cheaper
# than it was.
#
# Why this exists: on 2026-09-09 the assistant stopped answering. Cloud Run
# reported the service perfectly healthy — ContainerHealthy, 100% traffic,
# public invoker — while every request failed in ~0.1s. The cause was one line
# in the Cloud Run request log:
#
#     The request failed because billing is disabled for this project.
#
# The project's billing account had been closed, so Cloud Run refused requests
# before they reached the container. Nothing was wrong with the code, the image,
# or the rules. This script encodes the recovery so nobody has to rediscover it.
#
# It deliberately does NOT link billing. That is a financial decision about
# which account pays, and it belongs to a human — the script checks, tells you
# the exact command, and stops.
#
# Usage:  bash scripts/restore_ai_backend.sh
set -uo pipefail

PROJECT="stockmanagement-27af8"
SERVICE="rag-backend"
REGION="asia-south1"
URL="https://rag-backend-647731796550.asia-south1.run.app"

# Cost shape we want. min-instances=0 is the important one: at 1, a 2 vCPU /
# 1 GiB instance is held 24 hours a day whether or not anybody asks a question.
# max-instances bounds the worst case — every request can call a paid model, so
# an unbounded ceiling is an unbounded bill.
MIN_INSTANCES=0
MAX_INSTANCES=4

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

say "1. Billing"
BILLING=$(gcloud billing projects describe "$PROJECT" \
  --format="value(billingAccountName,billingEnabled)" 2>/dev/null)
ACCOUNT=$(echo "$BILLING" | awk '{print $1}' | sed 's|billingAccounts/||')
ENABLED=$(echo "$BILLING" | awk '{print $2}')

if [ -z "$ACCOUNT" ]; then
  fail "No billing account is linked to $PROJECT."
  ENABLED="False"
else
  OPEN=$(gcloud billing accounts describe "$ACCOUNT" --format="value(open)" 2>/dev/null)
  echo "   linked account : $ACCOUNT (open: ${OPEN:-unknown}, enabled: $ENABLED)"
  # billingEnabled only means an account is attached. A *closed* account is
  # still "enabled" here and still refuses every request, which is exactly what
  # made this outage hard to read.
  if [ "$OPEN" != "True" ]; then
    fail "   That account is closed, so Cloud Run will refuse every request."
    ENABLED="False"
  fi
fi

if [ "$ENABLED" != "True" ]; then
  echo
  fail "Billing must be restored first. Open accounts on this login:"
  gcloud billing accounts list --filter="open=true" \
    --format="table(ACCOUNT_ID,NAME)" 2>/dev/null | sed 's/^/   /'
  echo
  echo "   Then run, with the account you want to pay:"
  echo "     gcloud billing projects link $PROJECT --billing-account=ACCOUNT_ID"
  echo "   or use the console:"
  echo "     https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT"
  echo
  echo "   Re-run this script afterwards to apply the cost settings."
  exit 1
fi
ok "   Billing is live."

say "2. Cost settings"
echo "   min-instances -> $MIN_INSTANCES, max-instances -> $MAX_INSTANCES"
if gcloud run services update "$SERVICE" --region "$REGION" \
     --min-instances="$MIN_INSTANCES" --max-instances="$MAX_INSTANCES" \
     --quiet >/dev/null 2>&1; then
  ok "   Applied."
else
  fail "   Could not update the service. Run it by hand:"
  echo "     gcloud run services update $SERVICE --region $REGION \\"
  echo "       --min-instances=$MIN_INSTANCES --max-instances=$MAX_INSTANCES"
fi

say "3. Health"
# With min-instances at 0 the first request pays a cold start; the container
# measured ~6s to healthy, so give it a couple of tries before calling it dead.
for attempt in 1 2 3 4 5; do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 "$URL/health")
  if [ "$CODE" = "200" ]; then
    ok "   /health 200 on attempt $attempt — the assistant is answering."
    exit 0
  fi
  echo "   attempt $attempt: HTTP $CODE"
  sleep 5
done

fail "Still not healthy. Read the log line that actually explains it:"
echo "  gcloud logging read 'resource.type=\"cloud_run_revision\" AND"
echo "    resource.labels.service_name=\"$SERVICE\"' --limit 20 --freshness=1h \\"
echo "    --format='value(timestamp,severity,httpRequest.status,textPayload)'"
exit 1

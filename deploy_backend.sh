#!/bin/bash
set -euo pipefail

PROJECT_ID="stockmanagement-27af8"
REGION="asia-south1"
SERVICE="rag-backend"

cd "$(dirname "$0")/rag_backend"

echo "=== Running backend tests before deploy ==="
for suite in test_stock_math test_verify test_facts test_resolver test_cache test_pipeline test_create_product test_api_server test_swarm; do
  printf '  %-20s' "$suite"
  if ./venv/bin/python "$suite.py" >/dev/null 2>&1; then
    echo "PASS"
  else
    echo "FAIL — aborting deploy"
    ./venv/bin/python "$suite.py"
    exit 1
  fi
done

echo "=== Deploying $SERVICE to Cloud Run ==="
# --min-instances=1 removes cold starts (~\$8-12/month). Without it the first
# request after idle takes several seconds, which is why the client carried a
# retry loop.
# --cpu-boost speeds up container start when it does have to scale up.
gcloud run deploy "$SERVICE" \
  --source . \
  --region "$REGION" \
  --project "$PROJECT_ID" \
  --allow-unauthenticated \
  --min-instances=1 \
  --cpu-boost \
  --concurrency=40 \
  --memory=1Gi \
  --timeout=120 \
  --set-env-vars="ROUTER_MODEL=gemini-2.5-flash-lite,AGENT_MODEL=gemini-2.5-flash,HEAVY_MODEL=gemini-2.5-pro,GCP_PROJECT=$PROJECT_ID,GCP_LOCATION=$REGION,FACTS_TTL_SECONDS=45,FACTS_WINDOW_DAYS=90"

# Set GEMINI_API_KEY explicitly rather than relying on the silent fall-through
# to Vertex, so which provider serves a request is never a mystery:
#   gcloud run services update $SERVICE --region $REGION \
#     --update-secrets=GEMINI_API_KEY=gemini-api-key:latest

echo "=== Deployment complete ==="
gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT_ID" \
  --format='value(status.url)'

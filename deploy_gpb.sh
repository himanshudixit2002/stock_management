#!/bin/bash
set -euo pipefail

# The complete GPB pipeline: Android APK + web bundle + Firestore rules +
# Firestore indexes + Hosting, all against Firebase project gpbstockinventory.
#
# Entirely separate from deploy_all.sh, which is smartshelfkart.com's and
# touches a different Firebase project. The two share build/ and nothing else.
#
# That sharing is the one real hazard here. build/web is a single directory,
# and a web bundle carries its Firebase project compiled in, so the last build
# wins: never `firebase deploy` for one brand without rebuilding first, or
# smartshelfkart.com ships a bundle wired to gpbstockinventory. Both scripts
# start from `flutter clean` for exactly that reason.
#
#   ./deploy_gpb.sh              # build everything, then deploy everything
#   ./deploy_gpb.sh --build-only # build APK + web, deploy nothing
#   ./deploy_gpb.sh --aab        # also build an App Bundle for Play

PROJECT_ALIAS="gpb"
PROJECT_ID="gpbstockinventory"
CONFIG="firebase.gpb.json"
cd "$(dirname "$0")"

BUILD_ONLY=0
WANT_AAB=0
for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=1 ;;
    --aab)        WANT_AAB=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

echo "=== 1. Clean ==="
# `flutter build web` never prunes: deferred-import chunks from earlier builds
# survive in build/web and get listed in flutter_service_worker.js, so the
# service worker downloads and caches dead code. `flutter clean` is the only
# reliable prune -- and here it also guarantees no smartshelf artifacts remain.
flutter clean
flutter pub get

echo
echo "=== 2. Android APK (flavor: $PROJECT_ALIAS) ==="
# On Android the flavor is what matters: Gradle uses it to pick the
# applicationId and to bake src/gpb/google-services.json into the APK. The Dart
# side reads the same name back out via `appFlavor`.
flutter build apk --release --flavor "$PROJECT_ALIAS"

if [ "$WANT_AAB" -eq 1 ]; then
  echo
  echo "=== 2b. Android App Bundle ==="
  flutter build appbundle --release --flavor "$PROJECT_ALIAS"
fi

echo
echo "=== 3. Web ==="
# `flutter build web` rejects --flavor outright, so the brand travels as a
# dart-define instead. AppBrand.current reads it; see lib/config/flavor.dart.
flutter build web --release --dart-define=FLAVOR="$PROJECT_ALIAS"

echo
echo "=== 4. Verifying both artifacts target $PROJECT_ID ==="
# Cheap, and it catches the one failure that stays invisible until users hit
# it: a build that silently fell back to the default flavor.
APK=$(ls -t build/app/outputs/flutter-apk/*.apk 2>/dev/null | head -1)
[ -n "$APK" ] || { echo "ABORT: no APK produced." >&2; exit 1; }

# For the APK this is decisive: Gradle bakes exactly ONE google-services.json
# in per flavor, so the other project's id must be absent. Done in Python
# because resources.arsc string pools may be UTF-8 or UTF-16, and macOS
# `strings` cannot read the latter.
python3 - "$APK" "$PROJECT_ID" stockmanagement-27af8 <<'PYCHECK'
import sys, zipfile
apk, want, other = sys.argv[1], sys.argv[2], sys.argv[3]
blob = zipfile.ZipFile(apk).read("resources.arsc")
def present(needle):
    return needle.encode() in blob or needle.encode("utf-16-le") in blob
if not present(want):
    sys.exit(f"ABORT: {apk} never mentions {want} -- wrong google-services.json baked in.")
if present(other):
    sys.exit(f"ABORT: {apk} still mentions {other} -- flavor did not take effect.")
PYCHECK
echo "  APK  $APK -> $PROJECT_ID (and no trace of stockmanagement-27af8)"

# The web bundle only gets a positive check, deliberately. Both flavors'
# FirebaseOptions compile into every bundle -- config/firebase_app_options.dart
# imports both and picks at runtime, which dart2js cannot tree-shake -- so
# "the other project id is absent" would be false for a perfectly good build.
# These are public client identifiers, not secrets, so shipping both is
# harmless; it just means the bundle cannot tell you which one it will USE.
# Step 6 answers that properly, against the deployed site.
if ! grep -qr "$PROJECT_ID" build/web/*.js build/web/assets 2>/dev/null; then
  echo "ABORT: build/web has no reference to $PROJECT_ID." >&2
  exit 1
fi
echo "  web  build/web contains $PROJECT_ID (runtime target verified in step 6)"

if [ "$BUILD_ONLY" -eq 1 ]; then
  echo
  echo "=== Built, not deployed (--build-only) ==="
  echo "  $APK"
  exit 0
fi

echo
echo "=== 5. Deploying rules + indexes + hosting to $PROJECT_ID ==="
# No `node seo/build.mjs` here: the marketing site belongs to
# smartshelfkart.com, and firebase.gpb.json serves the app at / instead of /app.
firebase deploy \
  --only firestore:rules,firestore:indexes,hosting \
  --project "$PROJECT_ALIAS" \
  --config "$CONFIG"

echo
echo "=== 6. Post-deploy: a missing asset must 404, not return the app ==="
# This is a real regression guard, not a formality. Hosting serves a rewrite
# whenever no file matches, so a rewrite whose source is too broad turns every
# missing file into "200 text/html" -- a soft 404. Flutter loads each screen as
# a separate .part.js chunk, and a rebuild renames them. Any browser still
# asking for an older chunk name then gets index.html, tries to run HTML as
# JavaScript, and shows "Could not load this screen" on every deferred route.
# That is exactly what broke Safari (and not Chrome, which had revalidated).
SITE="https://$PROJECT_ID.web.app"
fail=0
probe() { curl -s -o /dev/null -w '%{http_code} %{content_type}' "$SITE$1"; }
for missing in /main.dart.js_9999.part.js /assets/definitely-not-here.png; do
  got=$(probe "$missing")
  case "$got" in
    404*) echo "  ok    $missing -> $got" ;;
    *)    echo "  FAIL  $missing -> $got (expected 404; the rewrite is too broad)" >&2; fail=1 ;;
  esac
done
for real in / /main.dart.js /flutter_service_worker.js; do
  got=$(probe "$real")
  case "$got" in
    200*) echo "  ok    $real -> $got" ;;
    *)    echo "  FAIL  $real -> $got (expected 200)" >&2; fail=1 ;;
  esac
done
[ "$fail" -eq 0 ] || { echo "Post-deploy checks failed." >&2; exit 1; }
echo
echo "  Still worth doing by hand: sign in and confirm the Firestore requests in"
echo "  DevTools > Network go to projects/$PROJECT_ID."
echo
echo "=== Done ==="
echo "  Web       https://$PROJECT_ID.web.app"
echo "  APK       $APK"
echo
echo "build/ now holds a $PROJECT_ALIAS build. Re-run ./deploy_all.sh (which cleans"
echo "first) before deploying smartshelfkart.com again."

#!/bin/bash
set -e

PROJECT_ID="stockmanagement-27af8"
cd /Users/himanshudixit/Desktop/stock_management

echo "=== 3. Building Flutter Web App ==="
# `flutter build web` never prunes: deferred-import chunks from earlier builds
# survive in build/web (and, because .dart_tool restores them, even survive an
# `rm -rf build/web`). They then get listed in flutter_service_worker.js, so the
# service worker downloads and caches dead code. A measured 25 of 76 part files
# (~714 KB) were orphaned this way. `flutter clean` is the only reliable prune.
flutter clean
flutter build web --release

echo "=== 3b. Building the static marketing site ==="
# MUST run after `flutter build web`, and MUST run before deploying. It moves
# the Flutter shell from index.html to app.html (so a crawlable homepage can
# live at "/"), renders the marketing pages, repoints the service worker at
# /app, and writes sitemap.xml and robots.txt. Deploying without this step
# publishes a site with no indexable content at all — which is the state this
# whole directory exists to fix.
node seo/build.mjs

echo "=== 4. Deploying Firebase Hosting ==="
firebase deploy --only hosting --project $PROJECT_ID || npx --yes firebase-tools deploy --only hosting --project $PROJECT_ID

echo "=== 5. Committing and Pushing to Git ==="
git add .
git commit -m "Enhance RAG backend pipeline and Flutter UI" || echo "No changes to commit"
git push

echo "=== Deployment Complete ==="
echo
echo "Post-deploy SEO checks:"
echo "  curl -sI https://smartshelfkart.com/            # 200, marketing homepage"
echo "  curl -s  https://smartshelfkart.com/robots.txt  # sitemap line present"
echo "  curl -sI https://smartshelfkart.com/app         # 200, Flutter shell"
echo "  curl -sI https://smartshelfkart.com/no-such-page # 404, not 200"

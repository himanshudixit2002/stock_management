#!/bin/bash
set -e

PROJECT_ID="stockmanagement-27af8"

echo "=== 3. Building Flutter Web App ==="
cd /Users/himanshudixit/Desktop/stock_management
# `flutter build web` never prunes: deferred-import chunks from earlier builds
# survive in build/web (and, because .dart_tool restores them, even survive an
# `rm -rf build/web`). They then get listed in flutter_service_worker.js, so the
# service worker downloads and caches dead code. A measured 25 of 76 part files
# (~714 KB) were orphaned this way. `flutter clean` is the only reliable prune.
flutter clean
flutter build web --release

echo "=== 4. Deploying Firebase Hosting ==="
firebase deploy --only hosting --project $PROJECT_ID || npx --yes firebase-tools deploy --only hosting --project $PROJECT_ID

echo "=== 5. Committing and Pushing to Git ==="
git add .
git commit -m "Enhance RAG backend pipeline and Flutter UI" || echo "No changes to commit"
git push

echo "=== Deployment Complete ==="

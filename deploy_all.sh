#!/bin/bash
set -e

PROJECT_ID="stockmanagement-27af8"

echo "=== 3. Building Flutter Web App ==="
cd /Users/himanshudixit/Desktop/stock_management
flutter build web --release

echo "=== 4. Deploying Firebase Hosting ==="
firebase deploy --only hosting --project $PROJECT_ID || npx --yes firebase-tools deploy --only hosting --project $PROJECT_ID

echo "=== 5. Committing and Pushing to Git ==="
git add .
git commit -m "Enhance RAG backend pipeline and Flutter UI" || echo "No changes to commit"
git push

echo "=== Deployment Complete ==="

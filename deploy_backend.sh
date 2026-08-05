#!/bin/bash
set -e

PROJECT_ID="stockmanagement-27af8"

echo "=== Building and Deploying RAG Backend to Cloud Run ==="
cd /Users/himanshudixit/Desktop/stock_management/rag_backend

gcloud run deploy rag-backend \
  --source . \
  --region asia-south1 \
  --project $PROJECT_ID \
  --allow-unauthenticated

echo "=== Backend Deployment Complete ==="

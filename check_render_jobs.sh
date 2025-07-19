#!/bin/bash

# This script helps check and trigger background jobs on Render

echo "=== Checking Background Job Logs ==="
echo "Please set ADMIN_TOKEN environment variable first"
echo ""

# Check logs
echo "Checking background job logs..."
curl -s "https://ai-dashboards.onrender.com/api/v1/admin/background_job_logs?token=$1" | jq

echo ""
echo "=== Triggering Manual Updates ==="

# Update data
echo "Updating PR data..."
curl -X POST https://ai-dashboards.onrender.com/api/v1/admin/update_data \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"$1\"}" | jq

echo ""
echo "Updating PR checks via API..."
curl -X POST https://ai-dashboards.onrender.com/api/v1/admin/update_checks_via_api \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"$1\"}" | jq

echo ""
echo "=== Checking a specific PR ==="
echo "Checking PR #23165..."
curl -s "https://ai-dashboards.onrender.com/api/v1/reviews" | jq '.pull_requests[] | select(.number == 23165)'
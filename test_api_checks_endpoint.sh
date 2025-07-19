#!/bin/bash

# Test updating a single PR
echo "Testing single PR update for #23012..."
curl -X POST https://ai-dashboards.onrender.com/api/v1/admin/update_checks_via_api \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"$ADMIN_TOKEN\", \"pr_number\": \"23012\"}"

echo -e "\n\nTesting single PR update for #23132..."
curl -X POST https://ai-dashboards.onrender.com/api/v1/admin/update_checks_via_api \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"$ADMIN_TOKEN\", \"pr_number\": \"23132\"}"

echo -e "\n\nTesting update all PRs..."
curl -X POST https://ai-dashboards.onrender.com/api/v1/admin/update_checks_via_api \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"$ADMIN_TOKEN\"}"
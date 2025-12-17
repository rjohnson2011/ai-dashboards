#!/bin/bash
# Script to trigger Render deployment programmatically
#
# Usage:
#   1. Get your deploy hook URL from Render Dashboard:
#      - Go to https://dashboard.render.com
#      - Select "ai-dashboards" service (or platform-code-reviews-api)
#      - Click Settings → Deploy Hook
#      - Copy the deploy hook URL
#
#   2. Set the RENDER_DEPLOY_HOOK environment variable:
#      export RENDER_DEPLOY_HOOK="https://api.render.com/deploy/srv-xxx?key=xxx"
#
#   3. Run this script:
#      ./scripts/trigger_deployment.sh

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Render Deployment Trigger${NC}"
echo "================================"

# Check if deploy hook URL is set
if [ -z "$RENDER_DEPLOY_HOOK" ]; then
  echo -e "${RED}Error: RENDER_DEPLOY_HOOK environment variable is not set${NC}"
  echo ""
  echo "To get your deploy hook URL:"
  echo "  1. Go to https://dashboard.render.com"
  echo "  2. Select your service (ai-dashboards or platform-code-reviews-api)"
  echo "  3. Click Settings → Deploy Hook"
  echo "  4. Copy the deploy hook URL"
  echo ""
  echo "Then set it:"
  echo "  export RENDER_DEPLOY_HOOK='https://api.render.com/deploy/srv-xxx?key=xxx'"
  exit 1
fi

echo "Triggering deployment..."
echo ""

# Trigger the deployment
response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" "$RENDER_DEPLOY_HOOK")
http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d: -f2)

if [ "$http_status" == "200" ] || [ "$http_status" == "201" ]; then
  echo -e "${GREEN}✓ Deployment triggered successfully!${NC}"
  echo ""
  echo "Deployment is now in progress. This typically takes 2-5 minutes."
  echo ""
  echo "Waiting 2 minutes before testing the verification endpoint..."
  sleep 120

  echo ""
  echo "Testing verification endpoint..."
  verify_response=$(curl -s "https://ai-dashboards.onrender.com/api/v1/admin/verify_scraper_version?token=${ADMIN_TOKEN}")

  if echo "$verify_response" | grep -q "git_commit"; then
    echo -e "${GREEN}✓ Verification endpoint is responding!${NC}"
    echo ""
    echo "Response:"
    echo "$verify_response" | python3 -m json.tool
  else
    echo -e "${YELLOW}⚠ Endpoint not yet available. Deployment may still be in progress.${NC}"
    echo "Try testing manually in a few minutes:"
    echo "  curl \"https://ai-dashboards.onrender.com/api/v1/admin/verify_scraper_version?token=\${ADMIN_TOKEN}\""
  fi
else
  echo -e "${RED}✗ Failed to trigger deployment${NC}"
  echo "HTTP Status: $http_status"
  echo "Response: $response"
  exit 1
fi

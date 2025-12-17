#!/bin/bash
# Fully programmatic deployment script using Render REST API
# No manual dashboard interaction required!
#
# One-time setup:
#   1. Create a Render API key programmatically or via: https://dashboard.render.com/u/settings#api-keys
#   2. export RENDER_API_KEY="rnd_xxxxx"
#   3. export ADMIN_TOKEN="your-admin-token"  # For verification endpoint
#
# Then simply run: ./scripts/deploy.sh

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Render Programmatic Deployment${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Check if RENDER_API_KEY is set
if [ -z "$RENDER_API_KEY" ]; then
  echo -e "${RED}Error: RENDER_API_KEY environment variable is not set${NC}"
  echo ""
  echo "To create an API key:"
  echo "  curl --request POST \\"
  echo "    --url 'https://api.render.com/v1/api-keys' \\"
  echo "    --header 'Authorization: Bearer YOUR_EXISTING_KEY' \\"
  echo "    --header 'Content-Type: application/json' \\"
  echo "    --data '{\"name\": \"deployment-automation\"}'"
  echo ""
  echo "Or visit: https://dashboard.render.com/u/settings#api-keys"
  echo ""
  echo "Then set it:"
  echo "  export RENDER_API_KEY='rnd_xxxxx'"
  exit 1
fi

echo -e "${YELLOW}Step 1:${NC} Fetching services from Render API..."
echo ""

# List all services and find the one we want
services_response=$(curl -s --request GET \
  --url 'https://api.render.com/v1/services' \
  --header 'Accept: application/json' \
  --header "Authorization: Bearer $RENDER_API_KEY")

# Check if API call succeeded
if echo "$services_response" | grep -q "error\|Unauthorized"; then
  echo -e "${RED}Error: Failed to fetch services${NC}"
  echo "$services_response"
  exit 1
fi

# Parse service list and find ai-dashboards or platform-code-reviews-api
echo "Found services:"
echo "$services_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        services = data
    else:
        services = data.get('services', data)

    target_service = None
    for service in services:
        name = service.get('name', '')
        service_id = service.get('id', '')
        service_type = service.get('type', '')
        print(f'  - {name} ({service_type}) [ID: {service_id}]')

        if name in ['ai-dashboards', 'platform-code-reviews-api']:
            target_service = service

    if target_service:
        print(f'\n✓ Found target service: {target_service[\"name\"]}')
        print(f'SERVICE_ID={target_service[\"id\"]}')
    else:
        print('\n✗ Target service not found')
        sys.exit(1)
except Exception as e:
    print(f'Error parsing services: {e}', file=sys.stderr)
    sys.exit(1)
" > /tmp/render_service_info.txt

# Check if service was found
if ! grep -q "SERVICE_ID=" /tmp/render_service_info.txt; then
  echo -e "${RED}Error: Could not find ai-dashboards or platform-code-reviews-api service${NC}"
  cat /tmp/render_service_info.txt
  exit 1
fi

cat /tmp/render_service_info.txt
SERVICE_ID=$(grep "SERVICE_ID=" /tmp/render_service_info.txt | cut -d'=' -f2)

echo ""
echo -e "${YELLOW}Step 2:${NC} Triggering deployment for service ID: ${SERVICE_ID}..."
echo ""

# Trigger the deployment
deploy_response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" --request POST \
  --url "https://api.render.com/v1/services/${SERVICE_ID}/deploys" \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer $RENDER_API_KEY")

http_status=$(echo "$deploy_response" | grep "HTTP_STATUS" | cut -d: -f2)

if [ "$http_status" == "200" ] || [ "$http_status" == "201" ]; then
  echo -e "${GREEN}✓ Deployment triggered successfully!${NC}"
  echo ""
  echo "Deploy response:"
  echo "$deploy_response" | grep -v "HTTP_STATUS" | python3 -m json.tool 2>/dev/null || echo "$deploy_response" | grep -v "HTTP_STATUS"
  echo ""
  echo -e "${YELLOW}Deployment is now in progress...${NC}"
  echo "This typically takes 2-5 minutes."
else
  echo -e "${RED}✗ Failed to trigger deployment${NC}"
  echo "HTTP Status: $http_status"
  echo "Response: $deploy_response"
  exit 1
fi

# Wait and verify
echo ""
echo -e "${YELLOW}Step 3:${NC} Waiting 2 minutes for deployment to complete..."
sleep 120

echo ""
echo -e "${YELLOW}Step 4:${NC} Testing verification endpoint..."
echo ""

if [ -z "$ADMIN_TOKEN" ]; then
  echo -e "${YELLOW}⚠ ADMIN_TOKEN not set, skipping verification${NC}"
  echo "To verify deployment later, run:"
  echo "  curl \"https://ai-dashboards.onrender.com/api/v1/admin/verify_scraper_version?token=\${ADMIN_TOKEN}\""
else
  verify_response=$(curl -s "https://ai-dashboards.onrender.com/api/v1/admin/verify_scraper_version?token=${ADMIN_TOKEN}")

  if echo "$verify_response" | grep -q "git_commit"; then
    echo -e "${GREEN}✓ Verification endpoint is responding!${NC}"
    echo ""
    echo "Response:"
    echo "$verify_response" | python3 -m json.tool
    echo ""

    # Check if git commit matches
    current_commit=$(git rev-parse HEAD | cut -c1-8)
    deployed_commit=$(echo "$verify_response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('git_commit', 'unknown'))" 2>/dev/null || echo "unknown")

    if [ "$current_commit" == "$deployed_commit" ]; then
      echo -e "${GREEN}✓ Deployed commit matches local commit: $current_commit${NC}"
      echo ""
      echo -e "${GREEN}================================${NC}"
      echo -e "${GREEN}  DEPLOYMENT SUCCESSFUL! ✓${NC}"
      echo -e "${GREEN}================================${NC}"
    else
      echo -e "${YELLOW}⚠ Commit mismatch:${NC}"
      echo "  Local:    $current_commit"
      echo "  Deployed: $deployed_commit"
      echo ""
      echo "Deployment may still be in progress. Wait a few more minutes and test again."
    fi
  else
    echo -e "${YELLOW}⚠ Endpoint not yet available. Deployment may still be in progress.${NC}"
    echo "Response: $verify_response"
    echo ""
    echo "Wait a few more minutes, then test manually:"
    echo "  curl \"https://ai-dashboards.onrender.com/api/v1/admin/verify_scraper_version?token=\${ADMIN_TOKEN}\""
  fi
fi

# Cleanup
rm -f /tmp/render_service_info.txt

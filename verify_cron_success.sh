#!/bin/bash
# Verify cron job is working after token fix

echo "🔍 Checking PR Dashboard After Token Fix"
echo "========================================"
echo ""

# Check API health
echo "1. API Health Check:"
HEALTH=$(curl -s -w "\nHTTP Status: %{http_code}" https://ai-dashboards.onrender.com/up)
echo "$HEALTH"
echo ""

# Check last update time
echo "2. Last Update Time:"
LAST_UPDATE=$(curl -s https://ai-dashboards.onrender.com/api/v1/reviews | jq -r '.last_updated')
echo "Last updated: $LAST_UPDATE"
echo ""

# Calculate time since last update
if [ "$LAST_UPDATE" != "null" ]; then
  LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_UPDATE%%.*}" "+%s" 2>/dev/null || date -d "${LAST_UPDATE}" "+%s" 2>/dev/null)
  NOW_EPOCH=$(date "+%s")
  DIFF=$((NOW_EPOCH - LAST_EPOCH))
  MINS=$((DIFF / 60))
  echo "Updated $MINS minutes ago"
fi
echo ""

# Check PR count
echo "3. PR Data:"
PR_DATA=$(curl -s https://ai-dashboards.onrender.com/api/v1/reviews)
OPEN_COUNT=$(echo "$PR_DATA" | jq '.count')
APPROVED_COUNT=$(echo "$PR_DATA" | jq '.approved_count')
echo "Open PRs: $OPEN_COUNT"
echo "Backend Approved PRs: $APPROVED_COUNT"
echo ""

# Check for admin token to see more details
if [ -n "$ADMIN_TOKEN" ]; then
  echo "4. Token Debug Info:"
  curl -s "https://ai-dashboards.onrender.com/api/v1/admin/debug_token?token=$ADMIN_TOKEN" | jq '.'
else
  echo "4. Set ADMIN_TOKEN to see debug info"
fi

echo ""
echo "✅ Success Indicators:"
echo "- Last update should be recent (< 30 mins if during business hours)"
echo "- PR counts should be > 0"
echo "- No rate limit errors in cron job logs"
echo ""
echo "Check Render Dashboard for cron job logs to confirm success!"
#!/bin/bash
# Check deployment and cron job status

echo "🔍 Checking Deployment Status"
echo "============================="
echo ""

# 1. Check if API is responding
echo "1. API Health Check:"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://ai-dashboards.onrender.com/up)
if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ API is up and running"
else
    echo "❌ API returned status: $HTTP_STATUS"
fi
echo ""

# 2. Check last update time
echo "2. Dashboard Data Status:"
API_DATA=$(curl -s https://ai-dashboards.onrender.com/api/v1/reviews)
LAST_UPDATE=$(echo "$API_DATA" | jq -r '.last_updated')
PR_COUNT=$(echo "$API_DATA" | jq -r '.count')
APPROVED_COUNT=$(echo "$API_DATA" | jq -r '.approved_count')

echo "Last updated: $LAST_UPDATE"
echo "Open PRs: $PR_COUNT"
echo "Backend Approved: $APPROVED_COUNT"

# Calculate time since update
if [ "$LAST_UPDATE" != "null" ] && [ -n "$LAST_UPDATE" ]; then
    # Handle both macOS and Linux date commands
    if date --version >/dev/null 2>&1; then
        # Linux
        LAST_EPOCH=$(date -d "${LAST_UPDATE}" "+%s" 2>/dev/null)
    else
        # macOS
        LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_UPDATE%%.*}" "+%s" 2>/dev/null)
    fi
    
    if [ -n "$LAST_EPOCH" ]; then
        NOW_EPOCH=$(date "+%s")
        DIFF=$((NOW_EPOCH - LAST_EPOCH))
        MINS=$((DIFF / 60))
        echo "Updated $MINS minutes ago"
    fi
fi
echo ""

# 3. Database migration check
if [ -n "$ADMIN_TOKEN" ]; then
    echo "3. Database Configuration Status:"
    DEBUG_INFO=$(curl -s "https://ai-dashboards.onrender.com/api/v1/admin/debug_token?token=$ADMIN_TOKEN")
    echo "$DEBUG_INFO" | jq '.'
    echo ""
fi

echo "📋 Next Steps:"
echo "1. Go to Render Shell and test migration:"
echo "   bundle exec rails db:migrate"
echo ""
echo "2. Check cron job logs in Render Dashboard:"
echo "   - Should show successful completion"
echo "   - No more 'unknown attribute head_sha' errors"
echo ""
echo "3. Monitor for next cron run (every 30 min during business hours)"
echo ""

# Show current time for reference
echo "Current time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Next cron runs at :00 and :30 of each hour"
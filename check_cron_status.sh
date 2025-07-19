#!/bin/bash
# Check if cron job is working and web service stopped polling

echo "Checking PR Dashboard Status"
echo "============================"

# Check if web service is still trying to update (it shouldn't be)
echo "1. Checking web service logs for background job attempts:"
echo "   (Should NOT see any BackgroundJobs entries after deploy)"
echo ""

# Check last update time
echo "2. Checking last update time:"
curl -s "https://ai-dashboards.onrender.com/api/v1/reviews" | jq '.last_updated'
echo ""

# Check for rate limit errors in admin endpoint
if [ -n "$ADMIN_TOKEN" ]; then
  echo "3. Checking background job logs:"
  curl -s "https://ai-dashboards.onrender.com/api/v1/admin/background_job_logs?token=$ADMIN_TOKEN" | jq '.'
else
  echo "3. Set ADMIN_TOKEN environment variable to check admin endpoints"
fi

echo ""
echo "Next Steps:"
echo "- Your web service should deploy in ~2 minutes"
echo "- No more rate limit errors after deploy!"
echo "- Check cron job logs in Render dashboard"
echo "- Cron job runs every 30 minutes during business hours"
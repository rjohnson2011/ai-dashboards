# Deployment Guide

## Problem: Production Not Auto-Deploying

If you push code to GitHub but it doesn't deploy automatically to Render, you need to manually trigger a deployment.

## Solution: Fully Programmatic Deployment via CLI

**No dashboard required!** Everything is done via Render's REST API.

### One-Time Setup

1. **Create a Render API Key** (one of two methods):

   **Method A: Via Dashboard** (Quick)
   - Go to https://dashboard.render.com/u/settings#api-keys
   - Click "Create API Key"
   - Name it "deployment-automation"
   - Copy the key (starts with `rnd_`)

   **Method B: Via CLI** (Fully programmatic - requires existing key)
   ```bash
   curl --request POST \
     --url 'https://api.render.com/v1/api-keys' \
     --header 'Authorization: Bearer YOUR_EXISTING_KEY' \
     --header 'Content-Type: application/json' \
     --data '{"name": "deployment-automation"}'
   ```

2. **Set environment variables:**
   ```bash
   export RENDER_API_KEY="rnd_xxxxx"
   export ADMIN_TOKEN="your-admin-token"  # For verification endpoint
   ```

   Or add to your `~/.zshrc` or `~/.bashrc`:
   ```bash
   echo 'export RENDER_API_KEY="rnd_xxxxx"' >> ~/.zshrc
   echo 'export ADMIN_TOKEN="your-admin-token"' >> ~/.zshrc
   ```

### Deploy!

Once configured, simply run:

```bash
./scripts/deploy.sh
```

This script will **automatically**:
1. Fetch all your services from Render API
2. Find the correct service (ai-dashboards or platform-code-reviews-api)
3. Trigger the deployment
4. Wait 2 minutes for deployment to complete
5. Test the verification endpoint
6. Compare deployed commit with local commit

**No manual dashboard interaction required!**

### Manual Alternative

If you prefer to use curl directly:

```bash
# 1. List services and find service ID
curl --request GET \
  --url 'https://api.render.com/v1/services' \
  --header 'Accept: application/json' \
  --header "Authorization: Bearer $RENDER_API_KEY"

# 2. Trigger deployment (replace SERVICE_ID)
curl --request POST \
  --url "https://api.render.com/v1/services/SERVICE_ID/deploys" \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer $RENDER_API_KEY"

# 3. Verify (wait 2-5 minutes)
curl "https://ai-dashboards.onrender.com/api/v1/admin/verify_scraper_version?token=$ADMIN_TOKEN" | python3 -m json.tool
```

### Verify New Code is Deployed

The verification endpoint should return:
```json
{
  "status": "ok",
  "git_commit": "01cb0e4",
  "git_commit_full": "01cb0e4d...",
  "hybrid_pr_checker_exists": true,
  "enhanced_scraper_exists": true,
  "fetch_all_pull_requests_job_path": ".../fetch_all_pull_requests_job.rb",
  "timestamp": "2025-12-17T19:30:00.000Z"
}
```

Check that `git_commit` matches your latest commit: `git rev-parse HEAD | cut -c1-8`

## Why Auto-Deploy Might Not Work

Render's auto-deploy can be disabled in the dashboard settings. If auto-deploy is enabled but not working:

1. Check the **Events** tab in Render dashboard for deployment logs
2. Look for build errors or failures
3. Ensure the GitHub webhook is properly configured
4. Try using the deploy hook URL as a workaround

## Troubleshooting

### Script says "RENDER_DEPLOY_HOOK environment variable is not set"
- Run the setup steps above to configure the deploy hook URL

### Endpoint returns 404 after deployment
- Wait a bit longer (deployments can take 3-5 minutes)
- Check Render dashboard → Events to see if deployment succeeded
- Ensure the route exists in `config/routes.rb`

### Deployment triggered but changes not visible
- Render cron jobs use Docker images that only rebuild when the web service redeploys
- Make sure you're triggering deployment for the web service (ai-dashboards), not the cron job
- After web service redeploys, the cron job will use the new Docker image on its next run

## Current Issue: PR #25417 Showing Incorrect Status

The fix for PR #25417 (and deduplication issues) is in commit `01cb0e4d`. After deploying this fix:

1. The next cron run (every 15 minutes) will use the new `HybridPrCheckerService`
2. PR #25417 should move from "Needing Backend Review" to "Finished but Unmerged"
3. Check times will drop from 10+ minutes to under 2 minutes

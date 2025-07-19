# Fix Cron Job Authentication Issue

## The Problem

Your cron job shows:
- Rate limit: `0/60` (unauthenticated)
- Should be: `5000/5000` (authenticated)

This means `GITHUB_TOKEN` is not set in the cron job environment!

## Immediate Fix

### 1. Add GitHub Token to Cron Job

In Render Dashboard:
1. Go to your `pr-scraper-cron` service
2. Click "Environment" tab
3. Add:
   - Key: `GITHUB_TOKEN`
   - Value: [Your GitHub Personal Access Token]
4. Click "Save Changes"

The cron job will use the token on next run.

### 2. Verify Other Required Environment Variables

Make sure ALL these are set in the cron job:
```
DATABASE_URL = [from your web service]
RAILS_ENV = production
RAILS_MASTER_KEY = [your key]
GITHUB_TOKEN = [your PAT] ⚠️ MISSING!
GITHUB_OWNER = department-of-veterans-affairs
GITHUB_REPO = vets-api
ADMIN_TOKEN = [your admin token]
```

## Why This Happened

- Environment variables are NOT automatically shared between services
- You must manually copy them to each service (web, cron, etc.)

## Alternative Solutions

### Option 1: Use Shared Environment Group (Recommended)

1. Create Environment Group in Render:
   - Dashboard → "Env Groups" → "New Environment Group"
   - Name: `shared-secrets`
   - Add all common variables

2. Link to both services:
   - Web service → Environment → Link `shared-secrets`
   - Cron job → Environment → Link `shared-secrets`

### Option 2: Use GitHub App Instead of PAT

GitHub Apps have higher rate limits:
- PAT: 5,000 requests/hour
- GitHub App: 15,000 requests/hour

### Option 3: Local Sync Script

If Render's IPs continue to be problematic, run from your local machine:

```bash
#!/bin/bash
# run_local_sync.sh
export ADMIN_TOKEN=your_token
export RAILS_ENV=production

while true; do
  echo "[$(date)] Syncing from local IP..."
  curl -X POST "https://ai-dashboards.onrender.com/api/v1/admin/update_full_data" \
    -H "Content-Type: application/json" \
    -d "{\"token\": \"$ADMIN_TOKEN\"}"
  
  echo "[$(date)] Sleeping 30 minutes..."
  sleep 1800
done
```

Run: `nohup ./run_local_sync.sh > sync.log 2>&1 &`

## Test After Adding Token

The next cron run should show:
```
GitHub API rate limit: 4999/5000  ✓ (authenticated)
```

Not:
```
GitHub API rate limit: 0/60  ✗ (unauthenticated)
```
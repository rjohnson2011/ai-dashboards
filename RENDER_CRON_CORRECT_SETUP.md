# Correct Render Cron Job Setup

## Important: Cron Jobs vs One-off Jobs

- **Cron Jobs**: Scheduled tasks created in Render Dashboard (what we need)
- **One-off Jobs**: Manually triggered tasks via API
- Cron jobs are NOT defined in render.yaml!

## Step-by-Step Setup

### 1. Create Cron Job in Render Dashboard

1. Go to [Render Dashboard](https://dashboard.render.com)
2. Click **"New +"** → **"Cron Job"**
3. Configure as follows:

**Connect Repository**
- Choose your GitHub repo: `ai-dashboards`
- Branch: `main`

**Configure Cron Job**
- **Name**: `pr-scraper-cron`
- **Environment**: `Ruby`
- **Build Command**: `./bin/render-build.sh`
- **Command**: `bundle exec rails runner scripts/render_cron_scraper_fixed.rb`
- **Schedule**: `0,30 13-22 * * MON-FRI`
  - This runs every 30 minutes, 1 PM - 10 PM UTC (9 AM - 6 PM EST)
  - Note: Render uses UTC time!
- **Instance Type**: `Starter` (sufficient for scraping)

### 2. Add Environment Variables

Click "Advanced" and add all these environment variables:

```
DATABASE_URL = [copy from your web service]
RAILS_ENV = production
RAILS_MASTER_KEY = [your master key]
GITHUB_TOKEN = [your GitHub PAT]
GITHUB_OWNER = department-of-veterans-affairs
GITHUB_REPO = vets-api
ADMIN_TOKEN = [your admin token]
```

**Important**: You need to manually copy these from your web service!

### 3. Create the Cron Job

Click **"Create Cron Job"**

### 4. Update Your Web Service

Remove the old background job from puma.rb:

```bash
# Copy the cleaner puma config
cp config/puma_webhook.rb config/puma.rb

# Commit and push
git add config/puma.rb
git commit -m "Remove background job scheduler - using cron jobs now"
git push origin main
```

## Understanding the Schedule

`0,30 13-22 * * MON-FRI` means:
- Minutes: 0 and 30 (twice per hour)
- Hours: 13-22 UTC (9 AM - 6 PM EST / 8 AM - 5 PM EDT)
- Day of month: * (any)
- Month: * (any)
- Day of week: MON-FRI (Monday through Friday)

## Monitoring

1. Go to your cron job in Render Dashboard
2. Check the "Events" tab for run history
3. View logs for each run
4. You can manually trigger with "Run now" button

## Why This Works

Each cron job run:
- Gets a fresh container with a NEW IP address
- Doesn't share rate limits with your web service
- Runs independently of your main app

## Verify It's Working

After first run, check:
1. Logs show different IP than your web service
2. No rate limit errors
3. PR data updates in your dashboard

## Troubleshooting

### "Database connection failed"
Make sure DATABASE_URL is correctly copied from your web service

### "Rate limit exceeded"
Check the IP in logs - it should be different each run

### Job not appearing
Cron jobs are separate services - check "Cron Jobs" section in dashboard

## Cost

- Billed per second of runtime
- ~3 minutes per run × 2 runs/hour × 10 hours/day × 22 days/month
- Approximately 88 hours/month
- Minimal cost on Starter instance (~$7/month)
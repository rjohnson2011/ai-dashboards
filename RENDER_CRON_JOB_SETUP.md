# Render Cron Job Setup (Paid Plan)

With Render's paid plan, you can use cron jobs that run with different IP addresses, avoiding GitHub's rate limits!

## How Cron Jobs Solve the Rate Limit Problem

1. **Different IPs**: Each cron job runs in a separate container with its own IP
2. **No shared limits**: Doesn't share rate limits with your web service
3. **Scheduled updates**: Runs automatically during business hours
4. **Better reliability**: Render manages the infrastructure

## Setup Steps

### 1. Update Your render.yaml

Replace your current `render.yaml` with `render_with_cron.yaml`:

```bash
cp render_with_cron.yaml render.yaml
git add render.yaml
git commit -m "Add cron job configuration for PR scraping"
git push origin main
```

### 2. Update Render Dashboard Settings

1. Go to your [Render Dashboard](https://dashboard.render.com)
2. You'll see a new service will be created: `pr-scraper-cron`
3. Make sure all environment variables are synced:
   - `GITHUB_TOKEN`
   - `GITHUB_OWNER` 
   - `GITHUB_REPO`
   - `RAILS_MASTER_KEY`
   - `ADMIN_TOKEN`

### 3. Deploy the Cron Job

Once you push the updated `render.yaml`:
1. Render will automatically create the cron job service
2. It will run every 30 minutes during business hours (9 AM - 7 PM EST, Mon-Fri)
3. Check the logs to verify it's working

### 4. Remove Old Background Job from Puma

Since we're using cron jobs now, update your puma.rb:

```bash
cp config/puma_webhook.rb config/puma.rb
git add config/puma.rb
git commit -m "Remove background scheduler, using cron jobs instead"
git push origin main
```

## Monitoring Your Cron Job

### View Logs
1. Go to Render Dashboard
2. Click on `pr-scraper-cron` service
3. View "Logs" tab

### Check Job History
Look for entries like:
```
[2024-07-19 10:00:00] INFO: Starting Render Cron Job PR Scraper
[2024-07-19 10:00:00] INFO: Running from IP: 54.123.45.67
[2024-07-19 10:00:01] INFO: GitHub API rate limit: 4999/5000
[2024-07-19 10:02:45] INFO: Cron job completed successfully!
```

### Manual Trigger
You can manually run the job from Render:
1. Go to the cron job service
2. Click "Trigger Run"

## Schedule Details

The cron expression `*/30 9-19 * * 1-5` means:
- Every 30 minutes (`*/30`)
- Between 9 AM and 7 PM EST (`9-19`)
- Every day of month (`*`)
- Every month (`*`)
- Monday through Friday (`1-5`)

## Verify It's Working

Run this script to check the data is updating:

```bash
export ADMIN_TOKEN=your_admin_token
ruby verify_webhook_setup.rb
```

## Advantages Over Webhooks

1. **No approval needed** - Just your own cron job
2. **No rate limits** - Each job gets fresh API quota
3. **Predictable** - Runs on schedule
4. **Easy to monitor** - See logs in Render dashboard
5. **Retries** - Render automatically retries failed jobs

## Cost

- Cron jobs are included in Render's paid plans
- Each run counts toward your compute hours
- ~1,200 runs/month (every 30 min during business hours)
- Minimal cost since each run is short (~3 minutes)

## Troubleshooting

### "API rate limit exceeded"
- Check the job logs for the IP address
- Verify it's different from your web service IP
- Reduce frequency if needed

### "Database connection failed"
- Ensure DATABASE_URL is set in the cron job env vars
- Check if database is accessible

### Job not running
- Verify the service is deployed
- Check cron expression is valid
- Look for errors in Render dashboard
# Migrating from Polling to Webhooks

This guide explains how to migrate from the polling-based approach (which hits rate limits) to webhooks for real-time updates.

## Why Webhooks?

The polling approach has a critical issue:
- Render uses shared IP addresses
- GitHub rate limits by IP address
- Result: `403 - API rate limit exceeded for 54.188.71.94`

Webhooks solve this by:
- GitHub pushes updates to your app
- No API calls needed to detect changes
- Real-time updates
- No rate limit issues

## Migration Steps

### 1. Deploy Webhook Code

First, deploy the webhook-enabled version of your app:

```bash
git add .
git commit -m "Add webhook support for real-time PR updates"
git push origin main
```

Wait for Render to deploy the changes.

### 2. Run Database Migration

In Render dashboard:
1. Go to your web service
2. Click "Shell" tab
3. Run: `bundle exec rails db:migrate`

This adds the `head_sha` column to pull_requests and creates the webhook_events table.

### 3. Set Up Webhook Secret

Generate a secure secret:
```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

Add to Render environment variables:
- Key: `GITHUB_WEBHOOK_SECRET`
- Value: [your generated secret]

### 4. Configure GitHub Webhook

Follow the instructions in `WEBHOOK_SETUP.md` to add the webhook to your GitHub repository.

### 5. Initial Data Sync

Since webhooks only capture new events, sync existing data:

In Render shell:
```bash
bundle exec rails runner "FetchAllPullRequestsJob.perform_now"
```

### 6. Switch Puma Config (Optional)

To use the webhook-optimized Puma config:

```bash
cp config/puma_webhook.rb config/puma.rb
```

This removes the polling scheduler and adds only a cleanup job for old webhook events.

### 7. Verify Everything Works

1. Check webhook deliveries in GitHub (should show green checkmarks)
2. Make a test PR change and verify it updates in real-time
3. Check logs: `[Webhook] Pull request opened: #123`
4. Monitor webhook events: 
   ```
   curl "https://your-app.onrender.com/api/v1/admin/webhook_events?token=YOUR_ADMIN_TOKEN"
   ```

## What Changes

### Before (Polling)
- Background job runs every 15 minutes
- Makes ~60 API calls per run
- Hits rate limits from Render's IP
- 15-minute delay for updates

### After (Webhooks)
- Instant updates when PRs change
- Only scrapes check details when needed
- No polling = no rate limits
- Real-time dashboard

## Rollback Plan

If you need to rollback to polling:
1. Delete the webhook in GitHub
2. Restore original puma.rb: `git checkout main -- config/puma.rb`
3. Redeploy

## Monitoring

### Webhook Events Dashboard
```
GET /api/v1/admin/webhook_events?token=YOUR_ADMIN_TOKEN
```

Shows:
- Recent webhook events
- Failed events
- Processing times
- Event types breakdown

### Logs
Look for `[Webhook]` prefixed messages:
```
[Webhook] Pull request opened: #123
[Webhook] Check suite completed for PRs: 123, 124
[Webhook] PR review submitted on #125
```

## FAQ

**Q: Do webhooks use API calls?**
A: Only for fetching check details via scraping. The webhook itself doesn't count against rate limits.

**Q: What if GitHub can't reach my app?**
A: GitHub retries failed deliveries. You can also manually redeliver from the webhook settings.

**Q: How do I debug webhook issues?**
A: Check Recent Deliveries in GitHub webhook settings. Each delivery shows the full request/response.

**Q: Can I use both webhooks and polling?**
A: Yes, but it's not recommended. Webhooks provide better real-time updates without rate limit issues.
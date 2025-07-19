# GitHub Webhook Setup Guide

This guide explains how to configure GitHub webhooks for real-time PR updates without hitting API rate limits.

## Overview

Instead of polling GitHub's API (which hits rate limits from Render's shared IPs), webhooks push updates to your app whenever changes occur. This provides:

- Real-time updates
- No rate limit issues
- Lower server load
- Faster response times

## Prerequisites

1. Your Rails app deployed to Render with a public URL
2. Admin access to the GitHub repository
3. A secure webhook secret (we'll generate one)

## Step 1: Generate Webhook Secret

Generate a secure random secret:

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

Save this secret - you'll need it for both GitHub and your app.

## Step 2: Add Secret to Your App

### For Render Deployment:

1. Go to your Render dashboard
2. Navigate to your web service
3. Go to Environment → Environment Variables
4. Add: `GITHUB_WEBHOOK_SECRET` with the value from Step 1

### For Local Development:

Add to your `.env` file:
```
GITHUB_WEBHOOK_SECRET=your_generated_secret_here
```

## Step 3: Configure GitHub Webhook

1. Go to your GitHub repository (`department-of-veterans-affairs/vets-api`)
2. Navigate to Settings → Webhooks
3. Click "Add webhook"
4. Configure as follows:

**Payload URL:**
```
https://your-app-name.onrender.com/api/v1/github_webhooks
```

**Content type:** `application/json`

**Secret:** Paste the secret from Step 1

**SSL verification:** Enable SSL verification

**Which events would you like to trigger this webhook?**
Select "Let me select individual events" and check:
- Pull requests
- Pull request reviews
- Pull request review comments
- Check runs
- Check suites
- Statuses

**Active:** ✓ Check this box

5. Click "Add webhook"

## Step 4: Verify Webhook

After creating the webhook:

1. GitHub will send a `ping` event
2. Check your Rails logs for: `[Webhook] Ping received - webhook configured successfully!`
3. The webhook should show a green checkmark in GitHub

## Step 5: Run Database Migration

Run the migration to add `head_sha` to pull requests:

```bash
bundle exec rails db:migrate
```

## Step 6: Initial Data Sync

Since webhooks only capture new events, run an initial sync:

```bash
# On Render, use the Render shell or a one-off job:
bundle exec rails runner "FetchAllPullRequestsJob.perform_now"
```

## How It Works

1. **Pull Request Events**: When PRs are opened, closed, edited, or synchronized
   - Updates PR metadata
   - Queues job to fetch check details

2. **Review Events**: When reviews are submitted
   - Updates review data
   - Recalculates approval statuses

3. **Check Events**: When CI checks run or complete
   - Updates check statuses
   - Recalculates ready-for-review status

4. **Status Events**: When commit statuses change
   - Finds PRs with that commit
   - Updates their check information

## Monitoring

### Check Webhook Deliveries

1. Go to Settings → Webhooks in GitHub
2. Click on your webhook
3. Scroll down to "Recent Deliveries"
4. Green checkmarks = successful deliveries
5. Click on any delivery to see request/response details

### Rails Logs

Monitor webhook events in your Rails logs:
```
[Webhook] Pull request opened: #123
[Webhook] Check suite completed for PRs: 123, 124
[Webhook] PR review submitted on #125
```

### Error Handling

The webhook controller includes:
- Signature verification (rejects unauthorized requests)
- Error logging for debugging
- Graceful error handling (returns 500 on errors)

## Troubleshooting

### Webhook Returns 401 Unauthorized
- Check that `GITHUB_WEBHOOK_SECRET` matches exactly
- Ensure no extra whitespace in the secret

### Webhook Returns 404
- Verify the payload URL is correct
- Check that your routes are properly configured
- Ensure your app is deployed and running

### Missing Updates
- Check "Recent Deliveries" in GitHub
- Look for errors in Rails logs
- Verify the correct events are selected

### Rate Limit Issues Persist
- Webhooks don't use API calls for receiving events
- Only the background jobs (fetching check details) use API calls
- These are spread out and shouldn't hit rate limits

## Security Notes

1. **Always verify signatures**: The webhook controller verifies every request
2. **Use HTTPS**: Ensure your Render app has SSL enabled
3. **Keep secret secure**: Never commit the webhook secret to git
4. **Monitor deliveries**: Regularly check for failed deliveries

## Benefits Over Polling

1. **No IP-based rate limits**: Webhooks push to you, not pull from GitHub
2. **Real-time updates**: Changes appear immediately
3. **Efficient**: Only processes actual changes
4. **Scalable**: Handles high-activity repos without issues
# Quick Webhook Setup Guide

## Your webhook configuration details:

### 1. Webhook Secret (already generated):
```
93b99cc9b4baf03089f3fbcbd9764c2dcb5a2aa9e28db03a37b6aaf576b2a556
```

### 2. Add to Render Environment:
1. Go to https://dashboard.render.com
2. Select your web service
3. Go to Environment → Environment Variables
4. Add:
   - Key: `GITHUB_WEBHOOK_SECRET`
   - Value: `93b99cc9b4baf03089f3fbcbd9764c2dcb5a2aa9e28db03a37b6aaf576b2a556`

### 3. Run Database Migration:
Once deployment completes:
1. In Render dashboard → Shell tab
2. Run: `bundle exec rails db:migrate`

### 4. Configure GitHub Webhook:
1. Go to: https://github.com/department-of-veterans-affairs/vets-api/settings/hooks/new
2. Fill in:
   - **Payload URL**: `https://ai-dashboards.onrender.com/api/v1/github_webhooks`
   - **Content type**: `application/json`
   - **Secret**: `93b99cc9b4baf03089f3fbcbd9764c2dcb5a2aa9e28db03a37b6aaf576b2a556`
   - **Which events?**: Select "Let me select individual events"
     - ✓ Check runs
     - ✓ Check suites  
     - ✓ Pull requests
     - ✓ Pull request reviews
     - ✓ Pull request review comments
     - ✓ Statuses
   - **Active**: ✓ (checked)
3. Click "Add webhook"

### 5. Initial Data Sync:
In Render Shell:
```bash
bundle exec rails runner "FetchAllPullRequestsJob.perform_now"
```

### 6. Verify Setup:
Run locally:
```bash
export ADMIN_TOKEN=your_admin_token
export API_URL=https://ai-dashboards.onrender.com
ruby verify_webhook_setup.rb
```

## Quick Test:
After setup, test by:
1. Edit any PR title in the repo
2. Check webhook deliveries in GitHub (should show green ✓)
3. Check your dashboard - PR should update immediately!
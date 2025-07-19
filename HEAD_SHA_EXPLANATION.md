# What is head_sha and Do We Need It?

## What head_sha Does

The `head_sha` column stores the commit SHA of the PR's head (latest commit). It's used for:

1. **Webhook Status Events**: When GitHub sends a "status" event (CI updates), it only includes the commit SHA, not the PR number. With `head_sha`, we can find which PRs are affected.

2. **Check Accuracy**: Ensures we're getting checks for the right commit, not an outdated one.

## Current Impact

**Without head_sha:**
- ✅ Cron job still works fine (I added the compatibility check)
- ✅ PR updates work normally
- ✅ Check scraping works
- ❌ Webhook status events can't find associated PRs
- ❌ Might get stale check data if PR is updated

**Do you need it?**
- If using **only cron jobs**: No, not critical
- If using **webhooks**: Yes, for status events
- For **best accuracy**: Yes, recommended

## The Migration Issue is More Important

Not being able to run migrations is a bigger problem than missing head_sha. This could prevent future updates and features.

## Quick Fix for Your Dashboard

Since you're using cron jobs (not webhooks), head_sha isn't critical. The cron job will work fine without it. But we should fix the migration issue for future updates.
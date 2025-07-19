# GitHub Actions Setup for PR Scraper

This guide explains how to set up the GitHub Actions workflow that scrapes PR checks every 30 minutes during business hours (M-F, 9AM-7PM EST).

## Required GitHub Secrets

You need to add the following secrets to your GitHub repository:

1. **Go to your repository on GitHub**
2. **Navigate to Settings → Secrets and variables → Actions**
3. **Click "New repository secret" for each of the following:**

### 1. `GH_PAT` (GitHub Personal Access Token)
- Your existing GitHub PAT with repo access
- This is the same token you use locally as `GITHUB_TOKEN`

### 2. `GITHUB_OWNER`
- Value: `department-of-veterans-affairs`

### 3. `GITHUB_REPO`
- Value: `vets-api`

### 4. `DATABASE_URL`
- Your production database connection string
- Format: `postgresql://username:password@host:port/database_name`
- This should be your Render database URL

### 5. `RAILS_MASTER_KEY`
- Found in `config/master.key` (do not commit this file!)
- Or get it from your Render environment variables

## Testing the Workflow

1. After adding all secrets, you can manually trigger the workflow:
   - Go to Actions tab in your repository
   - Click on "Scrape PR Checks" workflow
   - Click "Run workflow" button
   - Select branch and click "Run workflow"

2. Monitor the workflow execution:
   - Check the logs for any errors
   - Verify data is being updated in your database

## Schedule Details

The workflow runs on this schedule:
- **Days**: Monday through Friday only
- **Hours**: Every 30 minutes from 9 AM to 7 PM EST
- **Frequency**: 20 runs per day, 100 runs per week
- **Monthly usage**: ~1,299 minutes (well under the 2,000 free tier)

The cron expression `0,30 13-22 * * 1-5` means:
- Minutes 0 and 30 (every half hour)
- Hours 13-22 UTC (which is 9 AM - 6 PM EST or 9 AM - 7 PM EDT)
- Any day of month (*)
- Any month (*)
- Days 1-5 (Monday through Friday)

## Monitoring

- Check the Actions tab regularly for failed runs
- Failed runs will upload logs as artifacts for debugging
- The workflow will skip runs if API rate limit is too low

## Cost

This schedule keeps you well within GitHub's free tier of 2,000 minutes per month for private repositories.
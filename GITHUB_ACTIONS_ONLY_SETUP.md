# GitHub Actions-Only Setup (No Webhooks Required)

This approach uses GitHub Actions to push data to your app, avoiding the need for webhooks.

## How it Works

Instead of GitHub pushing to your app via webhooks, your GitHub Action will:
1. Run on PR/check events
2. Scrape the PR data
3. POST it to your API endpoint

## Setup Steps

### 1. Create a Personal Access Token
1. Go to https://github.com/settings/tokens/new
2. Create a token with `repo` scope
3. Copy the token

### 2. Fork the Repository (if needed)
If you can't add Actions to vets-api directly:
1. Fork `department-of-veterans-affairs/vets-api` to your account
2. Set up Actions in your fork
3. It will still track the upstream PRs

### 3. Add the GitHub Action
Create `.github/workflows/pr-dashboard-sync.yml` in YOUR fork:

```yaml
name: Sync PR Data to Dashboard

on:
  schedule:
    # Run every 30 minutes during business hours
    - cron: '0,30 13-22 * * 1-5'
  
  # Also run on PR events in your fork
  pull_request:
    types: [opened, closed, reopened, synchronize]
  
  # Manual trigger
  workflow_dispatch:

jobs:
  sync:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
    
    - name: Get PR Data
      id: pr_data
      uses: actions/github-script@v7
      with:
        github-token: ${{ secrets.GITHUB_TOKEN }}
        script: |
          // Get all open PRs from upstream
          const owner = 'department-of-veterans-affairs';
          const repo = 'vets-api';
          
          const prs = await github.rest.pulls.list({
            owner,
            repo,
            state: 'open',
            per_page: 100
          });
          
          // Get check status for each PR
          const prData = await Promise.all(prs.data.map(async (pr) => {
            const checks = await github.rest.checks.listForRef({
              owner,
              repo,
              ref: pr.head.sha
            });
            
            return {
              number: pr.number,
              title: pr.title,
              author: pr.user.login,
              head_sha: pr.head.sha,
              html_url: pr.html_url,
              created_at: pr.created_at,
              updated_at: pr.updated_at,
              draft: pr.draft,
              checks: checks.data
            };
          }));
          
          return prData;
    
    - name: Send to Dashboard API
      env:
        DASHBOARD_API_URL: ${{ secrets.DASHBOARD_API_URL }}
        DASHBOARD_API_TOKEN: ${{ secrets.DASHBOARD_API_TOKEN }}
      run: |
        curl -X POST "$DASHBOARD_API_URL/api/v1/github_actions/sync" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $DASHBOARD_API_TOKEN" \
          -d '${{ steps.pr_data.outputs.result }}'
```

### 4. Add Secrets to Your Fork
In your fork's settings → Secrets:
- `DASHBOARD_API_URL`: https://ai-dashboards.onrender.com
- `DASHBOARD_API_TOKEN`: Your admin token

### 5. Create API Endpoint
Add this endpoint to handle GitHub Actions data:

```ruby
# app/controllers/api/v1/github_actions_controller.rb
class Api::V1::GithubActionsController < ApplicationController
  before_action :authenticate_github_action
  
  def sync
    pr_data = JSON.parse(request.body.read)
    
    pr_data.each do |pr_info|
      pr = PullRequest.find_or_initialize_by(number: pr_info['number'])
      pr.update!(
        title: pr_info['title'],
        author: pr_info['author'],
        head_sha: pr_info['head_sha'],
        url: pr_info['html_url'],
        pr_created_at: pr_info['created_at'],
        pr_updated_at: pr_info['updated_at'],
        draft: pr_info['draft']
      )
      
      # Process checks
      FetchPullRequestChecksJob.perform_later(pr.id)
    end
    
    head :ok
  end
  
  private
  
  def authenticate_github_action
    token = request.headers['Authorization']&.split(' ')&.last
    head :unauthorized unless token == ENV['ADMIN_TOKEN']
  end
end
```

## Benefits
- No webhooks needed
- No organizational approval required
- Runs in YOUR account/fork
- Still tracks all upstream PRs
- Free tier: 2,000 minutes/month
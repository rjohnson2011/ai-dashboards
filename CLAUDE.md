# Platform Code Reviews API

## Overview
Rails 8 API backend for the PR Dashboard application. Tracks pull requests, reviews, CI status, and sprint metrics for the VA.gov platform team.

## Architecture

### Hosting & Infrastructure
- **API Server**: Render.com free tier (512MB RAM limit)
- **Database**: Neon PostgreSQL (serverless, free tier)
- **Cron Jobs**: GitHub Actions (replaced Render cron jobs)
  - Runs every 15 minutes during business hours (Mon-Fri, 6am-6pm PT)
  - Workflow: `.github/workflows/pr-scraper.yml`
  - Triggers `manual_scraper_run` endpoint synchronously

### Key Constraints
- Free tier has 512MB RAM - scraper must run efficiently
- Server sleeps after inactivity - cannot use async job queue (jobs get lost)
- All scraper jobs run synchronously via `perform_now`

## Version
Current version: **4.0** (defined in `app/controllers/api/v1/reviews_controller.rb`)

## Key Files

### Controllers (`app/controllers/api/v1/`)
- `reviews_controller.rb` - Main PR data endpoint, version info
- `admin_controller.rb` - Admin endpoints including `manual_scraper_run`
- `sprint_metrics_controller.rb` - Sprint/team metrics and charts
- `github_webhooks_controller.rb` - GitHub webhook handler
- `repositories_controller.rb` - Multi-repo support

### Jobs (`app/jobs/`)
- `fetch_all_pull_requests_job.rb` - **Main scraper job** - fetches PRs, reviews, CI status
- `capture_daily_metrics_job.rb` - Daily snapshot for historical charts
- `fetch_backend_review_group_job.rb` - Syncs backend reviewer list from GitHub team

### Services (`app/services/`)
- `github_service.rb` - GitHub API wrapper (REST + GraphQL)
- `hybrid_pr_checker_service.rb` - CI status fetching
- `pr_timeline_service.rb` - PR activity timeline

### Models (`app/models/`)
- `pull_request.rb` - Core PR model with approval logic
- `pull_request_review.rb` - Review records (uses stable SHA256 hash for github_id)
- `check_run.rb` - CI check results
- `daily_snapshot.rb` - Historical metrics
- `backend_review_group_member.rb` - Backend team members

## Configuration

### Environment Variables (on Render)
- `DATABASE_URL` - Neon PostgreSQL connection string
- `GITHUB_TOKEN` - GitHub PAT for API access
- `GITHUB_OWNER` - Default: `department-of-veterans-affairs`
- `GITHUB_REPO` - Default: `vets-api`
- `ADMIN_TOKEN` - Token for admin endpoints
- `RAILS_MASTER_KEY` - Rails credentials key

### GitHub Actions Secrets
- `API_URL` - `https://ai-dashboards.onrender.com`
- `ADMIN_TOKEN` - Same as Render env var

## Important Notes

### Scraper Execution
The scraper MUST run synchronously (`perform_now`) because:
1. Rails uses `:async` job adapter which stores jobs in-memory
2. On free tier, server sleeps/restarts frequently
3. Async jobs get lost when server restarts

### Cache Invalidation
- Cache key includes scrape timestamp: `last_scrape:{owner}:{repo}`
- Scraper updates this timestamp when complete
- Frontend cache invalidates automatically after each scrape

### Review Deduplication
`github_service.rb` uses `Digest::SHA256.hexdigest(review[:id]).to_i(16) % (2**62)` for stable review IDs (Ruby's `.hash` method changes across restarts).

### Association Cache Issue (Fixed Jan 2026)
When reviews are updated via `destroy_all` + `create!`, ActiveRecord's association cache may still hold stale data. The `calculate_backend_approval_status` and `approval_summary` methods now call `pull_request_reviews.reload` before processing to ensure fresh data.

## Common Operations

### Manual Scraper Trigger
```bash
curl -X POST "https://ai-dashboards.onrender.com/api/v1/admin/manual_scraper_run?token=ADMIN_TOKEN&repository_name=vets-api&repository_owner=department-of-veterans-affairs"
```

### Check Cron Status
```bash
curl "https://ai-dashboards.onrender.com/api/v1/admin/cron_status?token=ADMIN_TOKEN"
```

### Check Version
```bash
curl "https://ai-dashboards.onrender.com/api/v1/reviews/version"
```

### Debug PR Status
```bash
curl "https://ai-dashboards.onrender.com/api/v1/admin/debug_pr?token=ADMIN_TOKEN&pr_number=12345"
# Add &fix=true to force recalculate the backend_approval_status
```

### Fix All PR Statuses
```bash
curl -X POST "https://ai-dashboards.onrender.com/api/v1/admin/fix_all_pr_statuses?token=ADMIN_TOKEN"
```

## Deployment
- Auto-deploys from `main` branch on push
- Render builds and deploys automatically
- Run `rubocop` before committing (per project rules)

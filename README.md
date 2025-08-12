# VA Platform Code Reviews Dashboard - API

A Rails API backend for tracking and managing pull requests across Department of Veterans Affairs repositories. This service provides real-time PR data, CI/CD status tracking, and team approval workflows.

## Overview

This API serves as the backend for the VA Platform Code Reviews Dashboard, automatically fetching and processing pull request data from GitHub, tracking review status, and providing analytics for team performance.

## Features

- **Automated PR Tracking**: Fetches and updates PR data every 15 minutes
- **CI/CD Integration**: Tracks GitHub Actions status and check results
- **Backend Team Reviews**: Special handling for VA backend team approvals
- **Historical Analytics**: Daily snapshots for trend analysis
- **Multi-Repository Support**: Configurable for any GitHub repository
- **GitHub OAuth**: Secure authentication for team members
- **Caching Strategy**: Efficient data caching to minimize API calls

## Tech Stack

- **Ruby on Rails 7.2** (API-only mode)
- **PostgreSQL** for data persistence
- **Redis** for caching (via solid_cache)
- **Sidekiq** for background jobs
- **Octokit** for GitHub API integration
- **Playwright** for web scraping CI status
- **Docker** for containerization

## Prerequisites

- Ruby 3.2+
- PostgreSQL 14+
- Redis (optional, for caching)
- GitHub Personal Access Token or OAuth App

## Installation

1. Clone the repository:
```bash
git clone https://github.com/department-of-veterans-affairs/platform-code-reviews-api.git
cd platform-code-reviews-api
```

2. Install dependencies:
```bash
bundle install
```

3. Set up the database:
```bash
rails db:create
rails db:migrate
rails db:seed
```

4. Configure credentials:
```bash
rails credentials:edit
```

Add the following:
```yaml
github:
  token: your_github_personal_access_token
  client_id: your_oauth_app_client_id
  client_secret: your_oauth_app_client_secret
  
admin_token: your_secure_admin_token
secret_key_base: your_secret_key_base
```

5. Set environment variables:
```bash
cp .env.example .env
```

Edit `.env`:
```env
# GitHub Configuration
GITHUB_TOKEN=ghp_your_personal_access_token
GITHUB_OWNER=department-of-veterans-affairs
GITHUB_REPO=vets-api

# OAuth Configuration (optional)
GITHUB_CLIENT_ID=your_oauth_app_id
GITHUB_CLIENT_SECRET=your_oauth_app_secret

# Frontend URL
FRONTEND_URL=http://localhost:5173

# Admin Token
ADMIN_TOKEN=your_secure_admin_token
```

## Development

Start the Rails server:
```bash
rails server
```

Run background jobs (in a separate terminal):
```bash
bundle exec sidekiq
```

### Running Scrapers Manually

```bash
# Fast scraper (15-minute intervals)
rails runner scripts/fast_pr_scraper.rb

# Full scraper (comprehensive update)
rails runner scripts/render_cron_scraper.rb

# Capture daily metrics
rails runner "CaptureDailyMetricsJob.perform_now"
```

## API Endpoints

### Public Endpoints

```
GET /api/v1/reviews
  Query params: repository_owner, repository_name
  Returns: Pull requests with review status

GET /api/v1/repositories
  Returns: List of configured repositories

GET /api/v1/pr_history
  Query params: days, repository_owner, repository_name
  Returns: Historical PR data for charts
```

### Authenticated Endpoints

```
POST /api/v1/auth/github
  Body: { code: "oauth_code" }
  Returns: JWT token and user info

GET /api/v1/auth/me
  Headers: Authorization: Bearer <token>
  Returns: Current user info
```

### Admin Endpoints

```
POST /api/v1/admin/refresh
  Headers: Authorization: Bearer <admin_token>
  Triggers manual PR data refresh

GET /api/v1/admin/jobs
  Headers: Authorization: Bearer <admin_token>
  Returns: Background job status
```

## Deployment

### Render.com

1. Create a new Web Service
2. Connect your GitHub repository
3. Use the included `render.yaml` for configuration
4. Set environment variables in Render dashboard
5. Deploy

### Docker

```bash
# Build the image
docker build -f Dockerfile.render -t platform-code-reviews-api .

# Run the container
docker run -p 3000:3000 \
  -e DATABASE_URL=postgresql://... \
  -e RAILS_MASTER_KEY=... \
  -e GITHUB_TOKEN=... \
  platform-code-reviews-api
```

## Background Jobs

The application uses several background jobs:

- **Fast PR Scraper**: Runs every 15 minutes, updates PR status
- **Full Scraper**: Runs twice daily, comprehensive update
- **Daily Metrics**: Captures snapshots at 6 PM EST
- **Backend Review Group**: Updates team member list daily

### Cron Schedule (configured in render.yaml)

```
*/15 * * * * - Fast PR scraper
0 7,19 * * * - Full scraper
0 23 * * * - Daily metrics (6 PM EST)
```

## Configuration

### Adding New Repositories

1. Add to `config/repositories.yml`:
```yaml
repositories:
  - owner: department-of-veterans-affairs
    name: vets-website
    display_name: "Vets Website"
    backend_review_required: false
```

2. Run seed task:
```bash
rails db:seed
```

### Backend Review Team

Update the team in `app/models/pull_request.rb`:
```ruby
BACKEND_REVIEWERS = ['username1', 'username2']
```

## Monitoring

### Health Checks

```bash
# Check API health
curl http://localhost:3000/health

# Check last update time
curl http://localhost:3000/api/v1/reviews | jq '.last_updated'
```

### Logs

- Application logs: `log/production.log`
- Cron logs: Check `CronJobLog` records
- Sidekiq logs: Available in Sidekiq Web UI

## Troubleshooting

### Common Issues

1. **GitHub Rate Limiting**
   - Check rate limit: `rails runner "puts GithubService.new.rate_limit.inspect"`
   - Solution: Use multiple tokens or reduce scraping frequency

2. **Memory Issues**
   - Reduce batch sizes in scrapers
   - Increase dyno size on Render

3. **Slow Scraping**
   - Check Playwright browser instances
   - Optimize database queries with includes

### Debug Commands

```bash
# Check PR count
rails runner "puts PullRequest.open.count"

# Test GitHub connection
rails runner scripts/debug_github_token.rb

# Check failing PRs
rails runner "puts PullRequest.where(ci_status: 'failure').pluck(:number)"
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Write tests for your changes
4. Commit changes: `git commit -am 'Add new feature'`
5. Push to branch: `git push origin feature/my-feature`
6. Submit a pull request

### Running Tests

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/pull_request_test.rb
```

## Security

- Never commit credentials or tokens
- Use Rails encrypted credentials for sensitive data
- Implement rate limiting for API endpoints
- Keep dependencies updated

## License

This project is part of the Department of Veterans Affairs platform tools.

## Support

For issues and questions:
- Create an issue in this repository
- Contact the VA Platform team
- Check logs in production for debugging

## Related Projects

- [ai-dashboards-frontend](https://github.com/department-of-veterans-affairs/ai-dashboards-frontend) - Frontend application
- [vets-api](https://github.com/department-of-veterans-affairs/vets-api) - Main VA API repository
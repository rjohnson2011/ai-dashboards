#!/usr/bin/env ruby
# Quick test version of the cron scraper

require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

logger.info "Starting Quick Test Cron Job"

begin
  # Test database connection
  ActiveRecord::Base.connection.execute("SELECT 1")
  logger.info "Database connection successful"

  # Initialize services
  github_service = GithubService.new
  scraper_service = EnhancedGithubScraperService.new
  logger.info "Services initialized"

  # Check rate limit
  rate_limit = github_service.rate_limit
  logger.info "GitHub API rate limit: #{rate_limit.remaining}/#{rate_limit.limit}"

  # Fetch just first 3 open PRs
  logger.info "Fetching first 3 open PRs..."
  open_prs = github_service.all_pull_requests(state: 'open').first(3)
  logger.info "Found #{open_prs.count} PRs"

  # Update just these PRs
  open_prs.each do |pr_data|
    pr = PullRequest.find_or_initialize_by(number: pr_data.number)
    pr.update!(
      github_id: pr_data.id,
      title: pr_data.title,
      author: pr_data.user.login,
      state: pr_data.state,
      url: pr_data.html_url,
      pr_created_at: pr_data.created_at,
      pr_updated_at: pr_data.updated_at,
      draft: pr_data.draft || false
    )
    logger.info "Updated PR ##{pr.number}: #{pr.title[0..50]}..."
  end

  # Test scraping for just first PR
  pr = PullRequest.where(state: 'open').first
  if pr
    logger.info "Testing scrape for PR ##{pr.number}..."
    result = scraper_service.scrape_pr_checks_detailed(pr.url)
    logger.info "Scrape result: #{result[:overall_status]}, #{result[:total_checks]} checks"

    # Test review update (this is where the error occurs)
    logger.info "Testing review update..."
    reviews = github_service.pull_request_reviews(pr.number)
    logger.info "Found #{reviews.count} reviews"

    pr.update_backend_approval_status!
    pr.update_ready_for_backend_review!
    pr.update_approval_status!
    logger.info "Successfully updated approval statuses"
  end

  logger.info "Quick test completed successfully!"

rescue => e
  logger.error "Error: #{e.class} - #{e.message}"
  logger.error e.backtrace.first(5).join("\n")
end

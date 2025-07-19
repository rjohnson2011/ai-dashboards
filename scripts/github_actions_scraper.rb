#!/usr/bin/env ruby
# GitHub Actions scraper for PR checks
# Runs every 30 minutes during business hours

require 'logger'

# Set up logging
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

logger.info "Starting GitHub Actions PR scraper"
logger.info "Environment: #{Rails.env}"
logger.info "Repository: #{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']}"

begin
  # Test database connection
  ActiveRecord::Base.connection.execute("SELECT 1")
  logger.info "Database connection successful"
  
  # Initialize services
  github_service = GithubService.new
  scraper_service = EnhancedGithubScraperService.new
  
  # Check rate limit before starting
  rate_limit = github_service.rate_limit
  logger.info "GitHub API rate limit: #{rate_limit.remaining}/#{rate_limit.limit}"
  
  if rate_limit.remaining < 100
    logger.warn "Low API rate limit, skipping run"
    exit 0
  end
  
  # Step 1: Fetch all open PRs
  logger.info "Fetching open pull requests..."
  start_time = Time.now
  
  open_prs = github_service.all_pull_requests(state: 'open')
  logger.info "Found #{open_prs.count} open PRs (took #{(Time.now - start_time).round(2)}s)"
  
  # Step 2: Update or create PR records
  logger.info "Updating PR records..."
  new_count = 0
  updated_count = 0
  
  open_prs.each do |pr_data|
    pr = PullRequest.find_or_initialize_by(number: pr_data.number)
    is_new = pr.new_record?
    
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
    
    is_new ? new_count += 1 : updated_count += 1
  end
  
  logger.info "Created #{new_count} new PRs, updated #{updated_count} existing PRs"
  
  # Step 3: Clean up closed/merged PRs
  logger.info "Cleaning up closed/merged PRs..."
  cleanup_count = 0
  
  PullRequest.where(state: 'open').find_each do |pr|
    github_pr = open_prs.find { |p| p.number == pr.number }
    if github_pr.nil?
      # PR no longer open, check if closed or merged
      begin
        actual_pr = github_service.pull_request(pr.number)
        pr.update!(state: actual_pr.merged ? 'merged' : 'closed')
        cleanup_count += 1
      rescue Octokit::NotFound
        pr.destroy
        cleanup_count += 1
      end
    end
  end
  
  logger.info "Cleaned up #{cleanup_count} closed/merged PRs"
  
  # Step 4: Scrape checks for each PR
  logger.info "Scraping PR checks..."
  scrape_errors = 0
  scrape_success = 0
  
  PullRequest.where(state: 'open').find_each do |pr|
    begin
      logger.info "Scraping checks for PR ##{pr.number}: #{pr.title[0..50]}..."
      
      # Scrape the checks
      result = scraper_service.scrape_pr_checks_detailed(pr.url)
      
      # Update PR with check counts
      pr.update!(
        ci_status: result[:overall_status] || 'unknown',
        total_checks: result[:total_checks] || 0,
        successful_checks: result[:successful_checks] || 0,
        failed_checks: result[:failed_checks] || 0
      )
      
      # Store failing checks in cache for ready_for_backend_review calculation
      if result[:failed_checks] > 0 && result[:checks].any?
        failing_checks = result[:checks].select { |c| ['failure', 'error', 'cancelled'].include?(c[:status]) }
        Rails.cache.write("pr_#{pr.id}_failing_checks", failing_checks, expires_in: 1.hour)
      else
        Rails.cache.delete("pr_#{pr.id}_failing_checks")
      end
      
      # Clear existing check runs and save new ones
      pr.check_runs.destroy_all
      result[:checks].each do |check|
        pr.check_runs.create!(
          name: check[:name],
          status: check[:status] || 'unknown',
          url: check[:url],
          description: check[:description],
          required: check[:required] || false,
          suite_name: check[:suite_name]
        )
      end
      
      scrape_success += 1
      
      # Small delay to avoid rate limiting
      sleep 0.5
      
    rescue => e
      logger.error "Error scraping PR ##{pr.number}: #{e.message}"
      scrape_errors += 1
    end
  end
  
  logger.info "Scraped #{scrape_success} PRs successfully, #{scrape_errors} errors"
  
  # Step 5: Update PR reviews and approval statuses
  logger.info "Updating PR reviews and approval statuses..."
  
  PullRequest.where(state: 'open').find_each do |pr|
    begin
      # Fetch reviews
      reviews = github_service.pull_request_reviews(pr.number)
      
      # Update reviews
      reviews.each do |review_data|
        PullRequestReview.find_or_create_by(
          pull_request_id: pr.id,
          github_id: review_data.id
        ).update!(
          user: review_data.user.login,
          state: review_data.state,
          submitted_at: review_data.submitted_at
        )
      end
      
      # Update backend approval status
      pr.update_backend_approval_status!
      
      # Update ready for backend review status
      pr.update_ready_for_backend_review!
      
      # Update approval status (for fully approved PRs)
      pr.update_approval_status!
      
    rescue => e
      logger.error "Error updating reviews for PR ##{pr.number}: #{e.message}"
    end
  end
  
  # Step 6: Update cache with completion time
  Rails.cache.write('last_refresh_time', Time.current)
  
  # Final stats
  total_time = Time.now - start_time
  final_rate_limit = github_service.rate_limit
  api_calls_used = rate_limit.remaining - final_rate_limit.remaining
  
  logger.info "=" * 60
  logger.info "Scraper completed successfully!"
  logger.info "Total time: #{total_time.round(2)} seconds"
  logger.info "API calls used: #{api_calls_used}"
  logger.info "Remaining API calls: #{final_rate_limit.remaining}/#{final_rate_limit.limit}"
  logger.info "=" * 60
  
rescue => e
  logger.error "Fatal error in scraper: #{e.message}"
  logger.error e.backtrace.join("\n")
  exit 1
end
#!/usr/bin/env ruby
# Render Cron Job Scraper - Fixed version that handles missing repository columns
# Runs as a separate job with its own IP allocation

require 'logger'
require 'net/http'
require 'json'

# Set up logging
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

logger.info "Starting Render Cron Job PR Scraper (Fixed Version)"
logger.info "Job ID: #{ENV['RENDER_INSTANCE_ID']}"
logger.info "Service: #{ENV['RENDER_SERVICE_NAME']}"
logger.info "Repository: #{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']}"

# Check if repository columns exist
has_repository_columns = PullRequest.column_names.include?("repository_name")
logger.info "Database has repository columns: #{has_repository_columns}"

# Validate GitHub token
if ENV['GITHUB_TOKEN'].blank?
  logger.error "GITHUB_TOKEN environment variable is not set!"
  raise "GITHUB_TOKEN not configured"
end

# Validate token format
token = ENV['GITHUB_TOKEN']
logger.info "GitHub token present: Yes (#{token.length} chars)"
logger.info "Token format valid: #{token.start_with?('ghp_') || token.start_with?('github_pat_')}"

begin
  # Create log entry
  cron_log = CronJobLog.create!(
    status: 'running',
    started_at: Time.current
  )
  logger.info "Cron job log ID: #{cron_log.id}"

  # Test database connection
  ActiveRecord::Base.connection.execute("SELECT 1")
  logger.info "Database connection successful"

  # Check our IP (for debugging rate limits)
  begin
    ip_response = Net::HTTP.get(URI('https://api.ipify.org?format=json'))
    current_ip = JSON.parse(ip_response)['ip']
    logger.info "Running from IP: #{current_ip}"
  rescue => e
    logger.warn "Could not determine IP: #{e.message}"
  end

  # Initialize services with detailed error handling
  begin
    logger.info "Creating GitHub client..."
    github_service = GithubService.new
    logger.info "GitHub client created successfully"

    scraper_service = EnhancedGithubScraperService.new
    hybrid_service = HybridPrCheckerService.new
  rescue => e
    logger.error "Failed to create GitHub service: #{e.class} - #{e.message}"
    logger.error "This usually means the token is invalid or malformed"
    raise e
  end

  # Check rate limit before starting
  begin
    logger.info "Checking rate limit..."
    rate_limit = github_service.rate_limit
    logger.info "GitHub API rate limit: #{rate_limit.remaining}/#{rate_limit.limit}"
  rescue Octokit::Unauthorized => e
    logger.error "GitHub authentication failed: #{e.message}"
    logger.error "Token appears to be invalid or expired"

    # Try a raw API call to debug
    require 'net/http'
    uri = URI('https://api.github.com/rate_limit')
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "token #{ENV['GITHUB_TOKEN']}"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    logger.error "Raw API response: #{res.code} - #{res.message}"
    logger.error "Response body: #{res.body[0..200]}..." if res.body
    raise "GitHub authentication failed"
  end

  if rate_limit.remaining < 100
    logger.error "Low API rate limit (#{rate_limit.remaining}), exiting"
    raise "API rate limit too low"
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

  # Get repository values
  repo_name = ENV['GITHUB_REPO'] || 'vets-api'
  repo_owner = ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs'

  open_prs.each do |pr_data|
    # Find PR by number only if repository columns don't exist
    pr = if has_repository_columns
      PullRequest.find_or_initialize_by(
        number: pr_data.number,
        repository_name: repo_name,
        repository_owner: repo_owner
      )
    else
      PullRequest.find_or_initialize_by(number: pr_data.number)
    end

    is_new = pr.new_record?

    update_attrs = {
      github_id: pr_data.id,
      title: pr_data.title,
      author: pr_data.user.login,
      state: pr_data.state,
      url: pr_data.html_url,
      pr_created_at: pr_data.created_at,
      pr_updated_at: pr_data.updated_at,
      draft: pr_data.draft || false,
      labels: pr_data.labels.map { |label| label.name }
    }

    # Only add repository columns if they exist
    if has_repository_columns
      update_attrs[:repository_name] = repo_name
      update_attrs[:repository_owner] = repo_owner
    end

    # Only add head_sha if column exists (for migration compatibility)
    if pr.has_attribute?(:head_sha)
      update_attrs[:head_sha] = pr_data.head.sha
    end

    pr.assign_attributes(update_attrs)

    # Skip validations if repository columns don't exist
    if has_repository_columns
      pr.save!
    else
      pr.save!(validate: false)
    end

    is_new ? new_count += 1 : updated_count += 1
  end

  logger.info "Created #{new_count} new PRs, updated #{updated_count} existing PRs"

  # Step 3: Clean up closed/merged PRs
  logger.info "Cleaning up closed/merged PRs..."
  cleanup_count = 0

  # Build scope based on whether repository columns exist
  pr_scope = if has_repository_columns
    PullRequest.where(state: 'open', repository_name: repo_name, repository_owner: repo_owner)
  else
    PullRequest.where(state: 'open')
  end

  pr_scope.find_each do |pr|
    github_pr = open_prs.find { |p| p.number == pr.number }
    if github_pr.nil?
      begin
        actual_pr = github_service.pull_request(pr.number)
        pr.state = actual_pr.merged ? 'merged' : 'closed'

        if has_repository_columns
          pr.save!
        else
          pr.save!(validate: false)
        end

        cleanup_count += 1
      rescue Octokit::NotFound
        pr.destroy
        cleanup_count += 1
      end
    end
  end

  logger.info "Cleaned up #{cleanup_count} closed/merged PRs"

  # Step 4: Scrape checks for each PR (in batches to avoid timeouts)
  logger.info "Scraping PR checks..."
  scrape_errors = 0
  scrape_success = 0

  # Process in smaller batches
  total_prs = pr_scope.count
  processed = 0

  pr_scope.find_in_batches(batch_size: 10) do |batch|
    logger.info "Processing batch: PRs #{processed + 1}-#{processed + batch.size} of #{total_prs}"

    batch.each do |pr|
      begin
        processed += 1
        logger.info "[#{processed}/#{total_prs}] Getting accurate checks for PR ##{pr.number}: #{pr.title[0..50]}..."

        # Use hybrid checker for accurate results
        result = hybrid_service.get_accurate_pr_checks(pr)

        # Update PR with check counts
        pr.assign_attributes(
          ci_status: result[:overall_status] || 'unknown',
          total_checks: result[:total_checks] || 0,
          successful_checks: result[:successful_checks] || 0,
          failed_checks: result[:failed_checks] || 0,
          pending_checks: result[:pending_checks] || 0
        )

        if has_repository_columns
          pr.save!
        else
          pr.save!(validate: false)
        end

        # Store failing checks in cache (disabled in production due to solid_cache setup)
        # TODO: Enable after running cache migrations
        # if result[:failed_checks] > 0 && result[:checks].any?
        #   failing_checks = result[:checks].select { |c| ['failure', 'error', 'cancelled'].include?(c[:status]) }
        #   Rails.cache.write("pr_#{pr.id}_failing_checks", failing_checks, expires_in: 1.hour)
        # else
        #   Rails.cache.delete("pr_#{pr.id}_failing_checks")
        # end

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

        # Small delay between requests
        sleep 0.5

      rescue => e
        logger.error "Error scraping PR ##{pr.number}: #{e.message}"
        scrape_errors += 1
      end
    end

    # Pause between batches
    logger.info "Completed batch, pausing..."
    sleep 2
  end

  logger.info "Scraped #{scrape_success} PRs successfully, #{scrape_errors} errors"

  # Step 5: Update PR reviews and approval statuses
  logger.info "Updating PR reviews and approval statuses..."
  review_errors = 0

  pr_scope.find_each do |pr|
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

      # Update statuses - these methods internally use save!
      # We need to temporarily skip validations
      if has_repository_columns
        pr.update_backend_approval_status!
        pr.update_ready_for_backend_review!
        pr.update_approval_status!
      else
        # Update attributes directly without validation
        pr.backend_approval_status = pr.calculate_backend_approval_status
        pr.ready_for_backend_review = pr.calculate_ready_for_backend_review

        # Check approval status
        if pr.fully_approved? && pr.approved_at.nil?
          pr.approved_at = Time.current
        elsif !pr.fully_approved? && pr.approved_at.present?
          pr.approved_at = nil
        end

        pr.save!(validate: false)
      end

    rescue => e
      logger.error "Error updating reviews for PR ##{pr.number}: #{e.message}"
      review_errors += 1
    end
  end

  # Step 6: Update cache with completion time
  Rails.cache.write('last_refresh_time', Time.current)

  # Clean up old webhook events if they exist
  if defined?(WebhookEvent)
    old_events = WebhookEvent.cleanup_old_events
    logger.info "Cleaned up #{old_events} old webhook events"
  end

  # Final stats
  total_time = Time.now - start_time
  final_rate_limit = github_service.rate_limit
  api_calls_used = rate_limit.remaining - final_rate_limit.remaining

  logger.info "=" * 60
  logger.info "Cron job completed successfully!"
  logger.info "Total time: #{total_time.round(2)} seconds"
  logger.info "API calls used: #{api_calls_used}"
  logger.info "Remaining API calls: #{final_rate_limit.remaining}/#{final_rate_limit.limit}"
  logger.info "Review errors: #{review_errors}"
  logger.info "=" * 60

  # Run daily metrics capture once per day between 7-8am UTC (when this job runs at 7am)
  current_hour = Time.current.utc.hour
  today = Date.current

  # Check for daily snapshot based on repository columns
  snapshot_exists = if has_repository_columns
    DailySnapshot.exists?(
      snapshot_date: today,
      repository_name: repo_name,
      repository_owner: repo_owner
    )
  else
    DailySnapshot.exists?(snapshot_date: today)
  end

  if current_hour == 7 && !snapshot_exists
    logger.info "Running daily metrics capture for #{today}..."
    begin
      if has_repository_columns
        CaptureDailyMetricsJob.perform_now(
          repository_name: repo_name,
          repository_owner: repo_owner
        )
      else
        CaptureDailyMetricsJob.perform_now
      end
      logger.info "Daily metrics captured successfully"
    rescue => e
      logger.error "Failed to capture daily metrics: #{e.message}"
    end
  end

  # Update log entry
  cron_log.update!(
    status: 'completed',
    completed_at: Time.current,
    prs_processed: scrape_success + scrape_errors,
    prs_updated: scrape_success
  )

  # Script completed successfully - no need to exit when using rails runner

rescue StandardError => e
  logger.error "="*60
  logger.error "FATAL ERROR IN CRON JOB"
  logger.error "="*60
  logger.error "Error Class: #{e.class}"
  logger.error "Error Message: #{e.message}"
  logger.error "Error Location: #{e.backtrace&.first}"
  logger.error ""
  logger.error "Full Backtrace:"
  logger.error e.backtrace&.join("\n")
  logger.error "="*60

  # Log to database for persistence
  begin
    if defined?(cron_log) && cron_log
      cron_log.update!(
        status: 'failed',
        error_class: e.class.to_s,
        error_message: e.message,
        error_backtrace: e.backtrace&.first(50)&.join("\n"),
        completed_at: Time.current
      )
    else
      CronJobLog.create!(
        status: 'failed',
        started_at: Time.current,
        completed_at: Time.current,
        error_class: e.class.to_s,
        error_message: e.message,
        error_backtrace: e.backtrace&.first(50)&.join("\n")
      )
    end
  rescue => log_error
    logger.error "Could not log to database: #{log_error.message}"
  end

  raise e  # Re-raise the error for rails runner to handle
rescue Exception => e
  # Catch absolutely everything
  logger.error "UNEXPECTED EXCEPTION: #{e.class} - #{e.message}"
  logger.error e.backtrace&.first(10)&.join("\n")
  raise e  # Re-raise the error for rails runner to handle
end

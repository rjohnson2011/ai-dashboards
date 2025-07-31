#!/usr/bin/env ruby
# Fast PR Scraper - Optimized for 15-minute cron runs
# Target execution time: <3 minutes

require 'logger'

# Set up logging
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

logger.info "Starting Fast PR Scraper (15-min cron)"
logger.info "Target execution time: <3 minutes"

begin
  start_time = Time.current

  # Check for overlapping runs
  if CronJobLog.where(status: 'running').where('started_at > ?', 20.minutes.ago).exists?
    logger.warn "Previous job still running or stale, exiting to prevent overlap"
    exit 0
  end

  # Create log entry
  cron_log = CronJobLog.create!(
    status: 'running',
    started_at: Time.current
  )

  # Initialize services
  github_service = GithubService.new
  # Use hybrid approach for better accuracy
  checker_service = HybridPrCheckerService.new

  # Check rate limit
  rate_limit = github_service.rate_limit
  logger.info "GitHub API rate limit: #{rate_limit.remaining}/#{rate_limit.limit}"

  if rate_limit.remaining < 100
    logger.error "Low API rate limit, exiting"
    cron_log.update!(
      status: 'failed',
      error_message: 'Low GitHub API rate limit',
      completed_at: Time.current
    )
    exit 1
  end

  # Step 1: Quick sync of PR list (API calls: ~2)
  logger.info "Fetching open PRs..."
  open_prs = github_service.all_pull_requests(state: 'open')
  logger.info "Found #{open_prs.count} open PRs"

  # Quick update of basic PR data
  open_pr_numbers = []
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
      draft: pr_data.draft || false,
      head_sha: pr_data.head.sha
    )
    open_pr_numbers << pr.number
  end

  # Mark closed PRs
  PullRequest.where(state: 'open').where.not(number: open_pr_numbers).update_all(state: 'closed')

  # Step 2: Smart selection of PRs to scrape
  # Prioritize: Recently updated, never scraped, or stale data
  prs_to_scrape = PullRequest.where(state: 'open')
    .where(
      'last_scraped_at IS NULL OR ' +
      'pr_updated_at > last_scraped_at OR ' +
      'last_scraped_at < ?',
      30.minutes.ago
    )
    .order(Arel.sql('CASE WHEN last_scraped_at IS NULL THEN 0 ELSE 1 END'),
           pr_updated_at: :desc)
    .limit(20) # Limit to keep under 3 minutes

  logger.info "Selected #{prs_to_scrape.count} PRs for check scraping"

  # Step 3: Parallel scraping with thread pool
  require 'concurrent'
  pool = Concurrent::FixedThreadPool.new(3) # 3 concurrent browsers max
  futures = []

  prs_scraped = 0
  prs_to_scrape.each_with_index do |pr, index|
    future = Concurrent::Future.execute(executor: pool) do
      begin
        logger.info "[#{index + 1}/#{prs_to_scrape.count}] Scraping PR ##{pr.number}"

        result = checker_service.get_accurate_pr_checks(pr)

        # Update PR with results
        pr.update!(
          ci_status: result[:overall_status],
          total_checks: result[:total_checks],
          successful_checks: result[:successful_checks],
          failed_checks: result[:failed_checks],
          last_scraped_at: Time.current
        )

        # Update check runs
        pr.check_runs.destroy_all
        result[:checks].each do |check|
          pr.check_runs.create!(
            name: check[:name],
            status: check[:status] || 'unknown',
            required: check[:required] || false,
            suite_name: check[:suite_name]
          )
        end

        { success: true, pr_number: pr.number }
      rescue => e
        logger.error "Error scraping PR ##{pr.number}: #{e.message}"
        { success: false, pr_number: pr.number, error: e.message }
      end
    end

    futures << future
  end

  # Wait for all scraping to complete
  results = futures.map(&:value)
  successful_scrapes = results.count { |r| r[:success] }

  logger.info "Scraping complete: #{successful_scrapes}/#{results.count} successful"

  # Step 4: Quick review sync for ALL open PRs (to catch backend approvals)
  logger.info "Updating reviews for all open PRs..."
  review_errors = 0
  backend_status_changes = 0

  # Get all open PRs to check for review updates
  all_open_prs = PullRequest.where(state: 'open')

  all_open_prs.each do |pr|
    begin
      # Store current backend approval status
      old_backend_status = pr.backend_approval_status

      reviews = github_service.pull_request_reviews(pr.number)

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

      pr.update_backend_approval_status!
      pr.update_ready_for_backend_review!
      pr.update_approval_status!

      # If backend approval changed, ALWAYS update checks (not just for scraped PRs)
      if old_backend_status != pr.backend_approval_status
        backend_status_changes += 1
        logger.info "Backend approval changed for PR ##{pr.number}: #{old_backend_status} -> #{pr.backend_approval_status}"

        # Re-run the check update to reflect the backend approval change
        result = checker_service.get_accurate_pr_checks(pr)
        pr.update!(
          ci_status: result[:overall_status],
          total_checks: result[:total_checks],
          successful_checks: result[:successful_checks],
          failed_checks: result[:failed_checks],
          pending_checks: result[:pending_checks] || 0,
          last_scraped_at: Time.current
        )

        # Update check runs
        pr.check_runs.destroy_all
        result[:checks].each do |check|
          pr.check_runs.create!(
            name: check[:name],
            status: check[:status] || 'unknown',
            required: check[:required] || false,
            suite_name: check[:suite_name]
          )
        end
      elsif pr.check_runs.where("name LIKE ?", "%backend approval%").empty?
        # Even if backend approval didn't change, ensure the check exists
        logger.info "PR ##{pr.number} missing backend approval check - adding it"

        result = checker_service.get_accurate_pr_checks(pr)
        pr.update!(
          ci_status: result[:overall_status],
          total_checks: result[:total_checks],
          successful_checks: result[:successful_checks],
          failed_checks: result[:failed_checks],
          pending_checks: result[:pending_checks] || 0,
          last_scraped_at: Time.current
        )

        pr.check_runs.destroy_all
        result[:checks].each do |check|
          pr.check_runs.create!(
            name: check[:name],
            status: check[:status] || 'unknown',
            required: check[:required] || false,
            suite_name: check[:suite_name]
          )
        end
        backend_status_changes += 1
      end
    rescue => e
      logger.error "Error updating reviews for PR ##{pr.number}: #{e.message}"
      review_errors += 1
    end
  end

  # Complete
  execution_time = Time.current - start_time
  final_rate_limit = github_service.rate_limit

  cron_log.update!(
    status: 'completed',
    completed_at: Time.current,
    prs_processed: prs_to_scrape.count,
    prs_updated: successful_scrapes
  )

  logger.info "="*60
  logger.info "Fast scraper completed!"
  logger.info "Execution time: #{execution_time.round(2)} seconds"
  logger.info "PRs scraped: #{successful_scrapes}/#{prs_to_scrape.count}"
  logger.info "Reviews updated: #{all_open_prs.count - review_errors}/#{all_open_prs.count}"
  logger.info "Backend approval changes: #{backend_status_changes}"
  logger.info "API calls used: #{rate_limit.remaining - final_rate_limit.remaining}"
  logger.info "="*60
  
  # Run daily metrics capture once per day between 9-10am UTC
  current_hour = Time.current.utc.hour
  today = Date.current
  
  if current_hour == 9 && !DailySnapshot.exists?(snapshot_date: today)
    logger.info "Running daily metrics capture for #{today}..."
    begin
      CaptureDailyMetricsJob.perform_now
      logger.info "Daily metrics captured successfully"
    rescue => e
      logger.error "Failed to capture daily metrics: #{e.message}"
    end
  end

rescue => e
  logger.error "FATAL ERROR: #{e.class} - #{e.message}"
  logger.error e.backtrace.first(5).join("\n")

  if defined?(cron_log) && cron_log
    cron_log.update!(
      status: 'failed',
      error_class: e.class.to_s,
      error_message: e.message,
      error_backtrace: e.backtrace.first(20).join("\n"),
      completed_at: Time.current
    )
  end

  exit 1
end

#!/usr/bin/env ruby
# Render Cron Job Wrapper - Calls the FetchAllPullRequestsJob
# This ensures all job logic (including new features) is automatically used
# No need to recreate cron jobs when the job class changes!

require 'logger'

# Set up logging
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

logger.info "=" * 80
logger.info "Starting Render Cron Job - Wrapper Version"
logger.info "=" * 80
logger.info "Job ID: #{ENV['RENDER_INSTANCE_ID']}"
logger.info "Service: #{ENV['RENDER_SERVICE_NAME']}"
logger.info "Repository: #{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']}"
logger.info ""

# Validate environment
if ENV['GITHUB_TOKEN'].blank?
  logger.error "GITHUB_TOKEN environment variable is not set!"
  raise "GITHUB_TOKEN not configured"
end

# Get repository values
repo_name = ENV['GITHUB_REPO'] || 'vets-api'
repo_owner = ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs'

logger.info "Target repository: #{repo_owner}/#{repo_name}"
logger.info ""

# Create log entry
begin
  cron_log = CronJobLog.create!(
    status: 'running',
    started_at: Time.current
  )
  logger.info "Cron job log ID: #{cron_log.id}"
rescue => e
  logger.warn "Could not create cron log: #{e.message}"
  cron_log = nil
end

begin
  # Test database connection
  ActiveRecord::Base.connection.execute("SELECT 1")
  logger.info "Database connection: OK"
  logger.info ""

  # Call the job class directly - this uses ALL the latest job code
  logger.info "Calling FetchAllPullRequestsJob.perform_now..."
  logger.info "This includes all features: scraping, reviews, verification, etc."
  logger.info ""

  start_time = Time.now

  # Perform the job synchronously
  FetchAllPullRequestsJob.perform_now(
    repository_name: repo_name,
    repository_owner: repo_owner
  )

  elapsed_time = Time.now - start_time

  logger.info ""
  logger.info "=" * 80
  logger.info "Cron job completed successfully!"
  logger.info "Total time: #{elapsed_time.round(2)} seconds"
  logger.info "=" * 80

  # Update log entry
  if cron_log
    cron_log.update!(
      status: 'completed',
      completed_at: Time.current
    )
  end

rescue StandardError => e
  logger.error "=" * 80
  logger.error "FATAL ERROR IN CRON JOB"
  logger.error "=" * 80
  logger.error "Error Class: #{e.class}"
  logger.error "Error Message: #{e.message}"
  logger.error "Error Location: #{e.backtrace&.first}"
  logger.error ""
  logger.error "Full Backtrace:"
  logger.error e.backtrace&.join("\n")
  logger.error "=" * 80

  # Log to database
  if cron_log
    begin
      cron_log.update!(
        status: 'failed',
        error_class: e.class.to_s,
        error_message: e.message,
        error_backtrace: e.backtrace&.first(50)&.join("\n"),
        completed_at: Time.current
      )
    rescue => log_error
      logger.error "Could not log to database: #{log_error.message}"
    end
  end

  raise e  # Re-raise for rails runner to handle
end

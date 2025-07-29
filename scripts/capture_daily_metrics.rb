#!/usr/bin/env ruby
# Script to capture daily PR metrics
# Run this once per day to track opened/closed/merged PRs

require 'logger'

logger = Logger.new(STDOUT)
logger.info "=== DAILY METRICS CRON JOB STARTED ==="
logger.info "Time: #{Time.current}"
logger.info "Environment: #{ENV['RAILS_ENV'] || 'development'}"
logger.info "Ruby version: #{RUBY_VERSION}"
logger.info "Rails root: #{Rails.root}"

begin
  # Run the job
  CaptureDailyMetricsJob.perform_now
  
  # Log success
  logger.info "Daily metrics captured successfully"
  logger.info "=== DAILY METRICS CRON JOB COMPLETED ==="
  
  # Also log to cron job log
  CronJobLog.create!(
    status: 'completed',
    started_at: Time.current - 1.minute,
    completed_at: Time.current
  )
rescue => e
  logger.error "Error capturing daily metrics: #{e.message}"
  logger.error e.backtrace.first(5).join("\n")
  
  # Log failure
  CronJobLog.create!(
    status: 'failed',
    started_at: Time.current - 1.minute,
    completed_at: Time.current,
    error_class: e.class.to_s,
    error_message: e.message,
    error_backtrace: e.backtrace.first(20).join("\n")
  )
  
  exit 1
end
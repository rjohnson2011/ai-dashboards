#!/usr/bin/env ruby

# Render Cron Scraper V3 - Fetches all configured repositories
# This script is designed to run on Render's cron service
# It fetches PRs for all repositories defined in config/repositories.yml

require 'logger'

# Initialize logger
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

start_time = Time.now
logger.info "============================================================"
logger.info "Starting Render Cron Scraper V3"
logger.info "============================================================"

begin
  # Log configured repositories
  logger.info "Configured repositories:"
  RepositoryConfig.all.each do |repo|
    logger.info "  - #{repo.owner}/#{repo.name}"
  end

  # Track results
  success_count = 0
  error_count = 0
  total_prs = 0

  # Fetch PRs for each configured repository
  RepositoryConfig.all.each do |repo|
    logger.info ""
    logger.info "Processing #{repo.owner}/#{repo.name}..."

    begin
      # Check rate limit before proceeding
      github_service = GithubService.new(owner: repo.owner, repo: repo.name)
      rate_limit = github_service.rate_limit
      logger.info "API rate limit: #{rate_limit.remaining}/#{rate_limit.limit}"

      if rate_limit.remaining < 100
        logger.warn "Skipping #{repo.name} due to low API rate limit (#{rate_limit.remaining})"
        next
      end

      # Count existing PRs for this repo
      before_count = PullRequest.where(
        repository_name: repo.name,
        repository_owner: repo.owner
      ).count

      # Run the fetch job
      FetchAllPullRequestsJob.perform_now(
        repository_name: repo.name,
        repository_owner: repo.owner
      )

      # Count PRs after fetch
      after_count = PullRequest.where(
        repository_name: repo.name,
        repository_owner: repo.owner
      ).count

      new_prs = after_count - before_count
      total_prs += after_count

      logger.info "✓ Successfully processed #{repo.name}"
      logger.info "  Total PRs: #{after_count} (#{new_prs} new)"
      success_count += 1

    rescue => e
      logger.error "✗ Error processing #{repo.name}: #{e.message}"
      logger.error e.backtrace.first(5).join("\n")
      error_count += 1
    end
  end

  # Log final summary
  duration = Time.now - start_time
  logger.info ""
  logger.info "============================================================"
  logger.info "Cron job completed!"
  logger.info "Repositories processed: #{success_count} successful, #{error_count} errors"
  logger.info "Total PRs in database: #{total_prs}"
  logger.info "Total time: #{duration.round(2)} seconds"

  # Show final PR distribution
  logger.info ""
  logger.info "PRs by repository:"
  PullRequest.group(:repository_name).count.sort_by { |_, count| -count }.each do |repo, count|
    logger.info "  #{repo}: #{count} PRs"
  end

  logger.info "============================================================"

rescue => e
  logger.error "Fatal error in cron job: #{e.message}"
  logger.error e.backtrace.join("\n")
  raise e
end

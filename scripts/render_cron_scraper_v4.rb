#!/usr/bin/env ruby

# Render Cron Scraper V4 - Fetches PRs and Reviews for all configured repositories
# This script fetches both PR data and PR reviews (approvals) for accurate tracking

require 'logger'

# Initialize logger
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

start_time = Time.now
logger.info "============================================================"
logger.info "Starting Render Cron Scraper V4"
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
  total_reviews_fetched = 0

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

      # Get all open PRs for this repository to fetch reviews
      open_prs = PullRequest.where(
        repository_name: repo.name,
        repository_owner: repo.owner,
        state: 'open'
      )

      logger.info "Fetching reviews for #{open_prs.count} open PRs..."
      reviews_count = 0

      open_prs.find_each do |pr|
        begin
          # Fetch reviews from GitHub
          reviews = github_service.pull_request_reviews(pr.number)

          if reviews.any?
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
            reviews_count += reviews.count
          end

          # Update approval status for this PR
          pr.update_backend_approval_status!
          pr.update_ready_for_backend_review!
          pr.update_approval_status!

        rescue => e
          logger.error "  Error fetching reviews for PR ##{pr.number}: #{e.message}"
        end
      end

      # Count PRs after fetch
      after_count = PullRequest.where(
        repository_name: repo.name,
        repository_owner: repo.owner
      ).count

      new_prs = after_count - before_count
      total_prs += after_count
      total_reviews_fetched += reviews_count

      logger.info "✓ Successfully processed #{repo.name}"
      logger.info "  Total PRs: #{after_count} (#{new_prs} new)"
      logger.info "  Reviews fetched: #{reviews_count}"
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
  logger.info "Total reviews fetched: #{total_reviews_fetched}"
  logger.info "Total time: #{duration.round(2)} seconds"

  # Show final PR distribution
  logger.info ""
  logger.info "PRs by repository:"
  PullRequest.group(:repository_name).count.sort_by { |_, count| -count }.each do |repo, count|
    logger.info "  #{repo}: #{count} PRs"
  end

  # Show sample of PRs with approvals
  logger.info ""
  logger.info "Sample PRs with approvals:"
  PullRequest.joins(:pull_request_reviews)
    .where(pull_request_reviews: { state: 'APPROVED' })
    .distinct
    .limit(5)
    .each do |pr|
      approved_by = pr.pull_request_reviews.where(state: 'APPROVED').pluck(:user).join(', ')
      logger.info "  PR ##{pr.number}: Approved by #{approved_by}"
    end

  logger.info "============================================================"

rescue => e
  logger.error "Fatal error in cron job: #{e.message}"
  logger.error e.backtrace.join("\n")
  raise e
end

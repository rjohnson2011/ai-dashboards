#!/usr/bin/env ruby
# Script to update reviews for all open PRs
# This ensures backend approval status is current

require 'logger'

logger = Logger.new(STDOUT)
logger.info "Starting review update for all open PRs"

begin
  github_service = GithubService.new

  # Get all open PRs
  open_prs = PullRequest.where(state: 'open').order(:number)
  logger.info "Found #{open_prs.count} open PRs to check"

  updated_count = 0
  backend_status_changes = []

  open_prs.each_with_index do |pr, index|
    begin
      logger.info "[#{index + 1}/#{open_prs.count}] Checking PR ##{pr.number}"

      # Store current backend approval status
      old_status = pr.backend_approval_status

      # Fetch latest reviews from GitHub
      reviews = github_service.pull_request_reviews(pr.number)

      # Update reviews in database
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

      # Track if backend approval status changed
      if old_status != pr.backend_approval_status
        backend_status_changes << {
          pr_number: pr.number,
          old_status: old_status,
          new_status: pr.backend_approval_status
        }
        logger.info "  Backend approval changed: #{old_status} -> #{pr.backend_approval_status}"

        # If backend approval changed, update the CI checks to reflect it
        hybrid_service = HybridPrCheckerService.new
        result = hybrid_service.get_accurate_pr_checks(pr)

        pr.update!(
          ci_status: result[:overall_status],
          total_checks: result[:total_checks],
          successful_checks: result[:successful_checks],
          failed_checks: result[:failed_checks],
          pending_checks: result[:pending_checks] || 0
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
      end

      # Also update other statuses
      pr.update_ready_for_backend_review!
      pr.update_approval_status!

      updated_count += 1
    rescue => e
      logger.error "Error updating PR ##{pr.number}: #{e.message}"
    end
  end

  logger.info "="*60
  logger.info "Review update completed!"
  logger.info "PRs updated: #{updated_count}/#{open_prs.count}"
  logger.info "Backend approval status changes: #{backend_status_changes.count}"

  if backend_status_changes.any?
    logger.info "\nBackend approval changes:"
    backend_status_changes.each do |change|
      logger.info "  PR ##{change[:pr_number]}: #{change[:old_status]} -> #{change[:new_status]}"
    end
  end

rescue => e
  logger.error "FATAL ERROR: #{e.class} - #{e.message}"
  logger.error e.backtrace.first(5).join("\n")
  exit 1
end

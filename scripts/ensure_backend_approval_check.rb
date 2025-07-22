#!/usr/bin/env ruby
# Script to ensure all open PRs have the backend approval check properly set

require 'logger'

logger = Logger.new(STDOUT)
logger.info "Ensuring backend approval check for all open PRs"

begin
  hybrid_service = HybridPrCheckerService.new

  # Get all open PRs
  open_prs = PullRequest.where(state: 'open')
  logger.info "Found #{open_prs.count} open PRs to check"

  fixed_count = 0

  open_prs.each_with_index do |pr, index|
    begin
      # Check if PR has backend approval check
      backend_check = pr.check_runs.find_by("name LIKE ?", "%backend approval%")

      if backend_check.nil?
        logger.info "[#{index + 1}/#{open_prs.count}] PR ##{pr.number} missing backend approval check - fixing..."

        # Run hybrid checker to get all checks including backend approval
        result = hybrid_service.get_accurate_pr_checks(pr)

        # Update PR with results
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

        fixed_count += 1
        logger.info "  Fixed PR ##{pr.number} - now has #{pr.total_checks} checks"
      else
        # Ensure status is correct based on backend approval
        expected_status = pr.backend_approval_status == 'approved' ? 'success' : 'pending'
        if backend_check.status != expected_status
          logger.info "[#{index + 1}/#{open_prs.count}] PR ##{pr.number} backend check has wrong status (#{backend_check.status} -> #{expected_status})"
          backend_check.update!(status: expected_status)
          fixed_count += 1
        end
      end
    rescue => e
      logger.error "Error checking PR ##{pr.number}: #{e.message}"
    end
  end

  logger.info "="*60
  logger.info "Backend approval check update completed!"
  logger.info "Fixed #{fixed_count} PRs"

rescue => e
  logger.error "FATAL ERROR: #{e.class} - #{e.message}"
  logger.error e.backtrace.first(5).join("\n")
  exit 1
end

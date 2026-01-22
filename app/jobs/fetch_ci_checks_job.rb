class FetchCiChecksJob < ApplicationJob
  queue_as :default

  # Lightweight job that ONLY fetches CI checks
  # Designed to fit within 512MB memory limit
  def perform(repository_name: nil, repository_owner: nil)
    Rails.logger.info "[FetchCiChecksJob] Starting CI checks fetch for #{repository_owner}/#{repository_name}"

    # Create services once
    hybrid_service = HybridPrCheckerService.new(owner: repository_owner, repo: repository_name)

    # Only fetch checks for open PRs that have a head_sha
    pr_ids = PullRequest.where(
      state: "open",
      repository_name: repository_name || ENV["GITHUB_REPO"],
      repository_owner: repository_owner || ENV["GITHUB_OWNER"]
    )
    .where.not(head_sha: nil)
    .where(draft: false)
    .pluck(:id)

    Rails.logger.info "[FetchCiChecksJob] Found #{pr_ids.count} PRs to check"

    updated_count = 0
    errors = []

    # Process in small batches to minimize memory
    pr_ids.each_slice(3) do |batch_ids|
      PullRequest.where(id: batch_ids).each do |pr|
        begin
          result = hybrid_service.get_accurate_pr_checks(pr)

          # Update PR with check counts
          pr.update!(
            ci_status: result[:overall_status] || "unknown",
            total_checks: result[:total_checks] || 0,
            successful_checks: result[:successful_checks] || 0,
            failed_checks: result[:failed_checks] || 0,
            pending_checks: result[:pending_checks] || 0
          )

          # Only store failed checks to save memory
          if result[:failed_checks] > 0 && result[:checks].any?
            pr.check_runs.destroy_all
            failed_checks_data = result[:checks]
              .select { |c| %w[failure error cancelled].include?(c[:status]) }
              .first(10)
              .map do |check|
                {
                  name: check[:name],
                  status: check[:status] || "unknown",
                  url: check[:url],
                  description: check[:description],
                  required: check[:required] || false,
                  suite_name: check[:suite_name],
                  pull_request_id: pr.id,
                  created_at: Time.current,
                  updated_at: Time.current
                }
              end
            CheckRun.insert_all(failed_checks_data) if failed_checks_data.any?
          end

          updated_count += 1

          # Rate limit protection
          sleep 0.2
        rescue => e
          errors << "PR ##{pr.number}: #{e.message}"
          Rails.logger.error "[FetchCiChecksJob] Error for PR ##{pr.number}: #{e.message}"
        end
      end

      # Force garbage collection after each batch
      GC.start(full_mark: false, immediate_sweep: true)
    end

    Rails.logger.info "[FetchCiChecksJob] Completed. Updated #{updated_count} PRs, #{errors.count} errors"

    { updated: updated_count, errors: errors.count }
  end
end

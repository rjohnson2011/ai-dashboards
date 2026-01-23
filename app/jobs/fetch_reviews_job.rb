class FetchReviewsJob < ApplicationJob
  queue_as :default

  # Lightweight job that ONLY fetches reviews and updates approval status
  # Designed to fit within 512MB memory limit
  def perform(repository_name: nil, repository_owner: nil)
    Rails.logger.info "[FetchReviewsJob] Starting reviews fetch for #{repository_owner}/#{repository_name}"

    github_service = GithubService.new(owner: repository_owner, repo: repository_name)

    # Check rate limit
    rate_limit = github_service.rate_limit
    if rate_limit.remaining < 100
      Rails.logger.warn "[FetchReviewsJob] Low API rate limit (#{rate_limit.remaining}), skipping"
      return
    end

    # Only fetch reviews for PRs that need them (not already approved)
    pr_ids = PullRequest.where(
      state: "open",
      repository_name: repository_name || ENV["GITHUB_REPO"],
      repository_owner: repository_owner || ENV["GITHUB_OWNER"]
    )
    .where.not(backend_approval_status: "approved")
    .where(draft: false)
    .pluck(:id)

    Rails.logger.info "[FetchReviewsJob] Found #{pr_ids.count} PRs needing review check"

    updated_count = 0
    errors = []

    # Process in small batches to minimize memory
    pr_ids.each_slice(5) do |batch_ids|
      PullRequest.where(id: batch_ids).each do |pr|
        begin
          # Fetch reviews from GitHub
          reviews = github_service.pull_request_reviews(pr.number)

          # Update reviews in database
          if reviews.any?
            pr.pull_request_reviews.destroy_all
            reviews.each do |review_data|
              PullRequestReview.create!(
                pull_request_id: pr.id,
                github_id: review_data.id,
                user: review_data.user.login,
                state: review_data.state,
                submitted_at: review_data.submitted_at
              )
            end
          end

          # Update approval status
          old_status = pr.backend_approval_status
          pr.update_backend_approval_status!
          pr.update_ready_for_backend_review!
          pr.update_approval_status!
          pr.update_awaiting_author_changes!

          if pr.backend_approval_status != old_status
            updated_count += 1
            Rails.logger.info "[FetchReviewsJob] PR ##{pr.number}: #{old_status} -> #{pr.backend_approval_status}"
          end

          # Rate limit protection
          sleep 0.1
        rescue => e
          errors << "PR ##{pr.number}: #{e.message}"
          Rails.logger.error "[FetchReviewsJob] Error for PR ##{pr.number}: #{e.message}"
        end
      end

      # Force garbage collection after each batch
      GC.start(full_mark: false, immediate_sweep: true)
    end

    Rails.logger.info "[FetchReviewsJob] Completed. Updated #{updated_count} PRs, #{errors.count} errors"

    { updated: updated_count, errors: errors.count }
  end
end

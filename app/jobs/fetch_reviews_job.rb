class FetchReviewsJob < ApplicationJob
  queue_as :default

  # Lightweight job that fetches reviews AND comments, updates approval status
  # Designed to fit within 512MB memory limit
  def perform(repository_name: nil, repository_owner: nil)
    Rails.logger.info "[FetchReviewsJob] Starting reviews/comments fetch for #{repository_owner}/#{repository_name}"

    github_service = GithubService.new(owner: repository_owner, repo: repository_name)

    # Check rate limit
    rate_limit = github_service.rate_limit
    if rate_limit.remaining < 100
      Rails.logger.warn "[FetchReviewsJob] Low API rate limit (#{rate_limit.remaining}), skipping"
      return
    end

    repo_filter = {
      repository_name: repository_name || ENV["GITHUB_REPO"],
      repository_owner: repository_owner || ENV["GITHUB_OWNER"]
    }

    # Fetch reviews for open PRs that aren't yet approved
    open_pr_ids = PullRequest.where(state: "open", **repo_filter)
      .where.not(backend_approval_status: "approved")
      .where(draft: false)
      .pluck(:id)

    # Also fetch reviews for recently merged/closed PRs (last 30 min) to capture
    # approvals that happened right before merge — otherwise these never get recorded
    recent_pr_ids = PullRequest.where(state: %w[merged closed], **repo_filter)
      .where("updated_at >= ?", 30.minutes.ago)
      .pluck(:id)

    pr_ids = (open_pr_ids + recent_pr_ids).uniq

    Rails.logger.info "[FetchReviewsJob] Found #{open_pr_ids.count} open + #{recent_pr_ids.count} recently merged PRs needing review check"

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

          # Fetch PR comments (issue comments) from GitHub
          fetch_pr_comments(pr, github_service)

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

  private

  def fetch_pr_comments(pr, github_service)
    comments = github_service.pull_request_comments(pr.number)
    return if comments.empty?

    # Only keep the last 20 comments to save space
    recent_comments = comments.last(20)

    # Get existing comment IDs to avoid duplicates
    existing_ids = pr.pull_request_comments.pluck(:github_id)

    recent_comments.each do |comment|
      next if existing_ids.include?(comment.id)

      PullRequestComment.create!(
        pull_request_id: pr.id,
        github_id: comment.id,
        user: comment.user.login,
        body: comment.body&.truncate(500), # Limit body length
        commented_at: comment.created_at
      )
    end

    # Clean up old comments (keep only last 20)
    comment_ids_to_keep = pr.pull_request_comments.order(commented_at: :desc).limit(20).pluck(:id)
    pr.pull_request_comments.where.not(id: comment_ids_to_keep).destroy_all if comment_ids_to_keep.any?
  rescue => e
    Rails.logger.warn "[FetchReviewsJob] Failed to fetch comments for PR ##{pr.number}: #{e.message}"
  end
end

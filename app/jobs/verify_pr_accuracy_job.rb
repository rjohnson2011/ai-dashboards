class VerifyPrAccuracyJob < ApplicationJob
  queue_as :default

  # Verifies that our stored PR data matches GitHub's actual state
  # Checks a sample of PRs to detect data drift without using too many API calls
  def perform(repository_name: nil, repository_owner: nil, sample_size: 20)
    repository_name ||= ENV["GITHUB_REPO"] || "vets-api"
    repository_owner ||= ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"

    Rails.logger.info "[VerifyPrAccuracyJob] Starting verification for #{repository_owner}/#{repository_name}"

    github_service = GithubService.new(owner: repository_owner, repo: repository_name)
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Get a sample of open PRs to verify
    # Prioritize PRs that are "Ready for Review" (most visible to users)
    prs_to_verify = PullRequest.where(
      state: "open",
      repository_name: repository_name,
      repository_owner: repository_owner,
      draft: false
    ).where(backend_approval_status: "not_approved")
      .order(pr_updated_at: :desc)
      .limit(sample_size)

    discrepancies = []
    verified_count = 0

    prs_to_verify.each do |pr|
      begin
        result = verify_single_pr(pr, github_service, backend_members)
        verified_count += 1

        if result[:discrepancy]
          discrepancies << result
          Rails.logger.warn "[VerifyPrAccuracyJob] Discrepancy found for PR ##{pr.number}: #{result[:message]}"

          # Auto-fix the discrepancy
          fix_pr_data(pr, github_service)
        end

        # Rate limit protection
        sleep 0.5
      rescue => e
        Rails.logger.error "[VerifyPrAccuracyJob] Error verifying PR ##{pr.number}: #{e.message}"
      end
    end

    # Also spot-check some "approved" PRs to make sure they're still approved
    approved_prs = PullRequest.where(
      state: "open",
      repository_name: repository_name,
      repository_owner: repository_owner,
      backend_approval_status: "approved"
    ).order(pr_updated_at: :desc).limit(10)

    approved_prs.each do |pr|
      begin
        result = verify_single_pr(pr, github_service, backend_members)
        verified_count += 1

        if result[:discrepancy]
          discrepancies << result
          Rails.logger.warn "[VerifyPrAccuracyJob] Discrepancy found for approved PR ##{pr.number}: #{result[:message]}"
          fix_pr_data(pr, github_service)
        end

        sleep 0.5
      rescue => e
        Rails.logger.error "[VerifyPrAccuracyJob] Error verifying approved PR ##{pr.number}: #{e.message}"
      end
    end

    Rails.logger.info "[VerifyPrAccuracyJob] Verification complete. Verified: #{verified_count}, Discrepancies: #{discrepancies.count}"

    {
      verified_count: verified_count,
      discrepancies_count: discrepancies.count,
      discrepancies: discrepancies
    }
  end

  private

  def verify_single_pr(pr, github_service, backend_members)
    # Fetch fresh reviews from GitHub
    github_reviews = github_service.pull_request_reviews(pr.number)

    # Calculate what the backend_approval_status SHOULD be
    reviews_by_user = github_reviews.group_by { |r| r.user.login }
    latest_actionable_reviews = reviews_by_user.map do |_user, reviews|
      actionable = reviews.reject { |r| r.state == "COMMENTED" }
      actionable.any? ? actionable.max_by(&:submitted_at) : reviews.max_by(&:submitted_at)
    end

    approved_users = latest_actionable_reviews
      .select { |r| r.state == "APPROVED" }
      .map { |r| r.user.login }

    should_be_approved = (approved_users & backend_members).any?
    expected_status = should_be_approved ? "approved" : "not_approved"

    if pr.backend_approval_status != expected_status
      {
        discrepancy: true,
        pr_number: pr.number,
        stored_status: pr.backend_approval_status,
        expected_status: expected_status,
        approved_users: approved_users,
        backend_approvers: approved_users & backend_members,
        message: "Status mismatch: stored=#{pr.backend_approval_status}, expected=#{expected_status}"
      }
    else
      { discrepancy: false, pr_number: pr.number }
    end
  end

  def fix_pr_data(pr, github_service)
    # Refetch and store all reviews
    reviews = github_service.pull_request_reviews(pr.number)

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

    # Recalculate statuses
    pr.update_backend_approval_status!
    pr.update_ready_for_backend_review!
    pr.update_approval_status!

    Rails.logger.info "[VerifyPrAccuracyJob] Fixed PR ##{pr.number}, new status: #{pr.backend_approval_status}"
  end
end

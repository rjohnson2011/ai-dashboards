class VerifyPrAccuracyJob < ApplicationJob
  queue_as :default

  # Comprehensive verification that our stored PR data matches GitHub's actual state
  # Checks: reviews (approvals, changes requested, comments), CI status, and check runs
  def perform(repository_name: nil, repository_owner: nil, sample_size: 20)
    repository_name ||= ENV["GITHUB_REPO"] || "vets-api"
    repository_owner ||= ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"

    Rails.logger.info "[VerifyPrAccuracyJob] Starting comprehensive verification for #{repository_owner}/#{repository_name}"

    github_service = GithubService.new(owner: repository_owner, repo: repository_name)
    hybrid_checker = HybridPrCheckerService.new(owner: repository_owner, repo: repository_name)
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Get a sample of open PRs to verify - prioritize recently updated
    prs_to_verify = PullRequest.where(
      state: "open",
      repository_name: repository_name,
      repository_owner: repository_owner,
      draft: false
    ).order(pr_updated_at: :desc).limit(sample_size)

    discrepancies = []
    verified_count = 0

    prs_to_verify.each do |pr|
      begin
        result = verify_single_pr(pr, github_service, hybrid_checker, backend_members)
        verified_count += 1

        if result[:has_discrepancy]
          discrepancies << result
          Rails.logger.warn "[VerifyPrAccuracyJob] Discrepancies found for PR ##{pr.number}"
          result[:issues].each { |issue| Rails.logger.warn "  - #{issue}" }

          # Auto-fix the discrepancy
          fix_pr_data(pr, github_service, hybrid_checker)
        end

        # Rate limit protection
        sleep 0.5
      rescue => e
        Rails.logger.error "[VerifyPrAccuracyJob] Error verifying PR ##{pr.number}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
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

  def verify_single_pr(pr, github_service, hybrid_checker, backend_members)
    issues = []

    # === VERIFY REVIEWS ===
    github_reviews = github_service.pull_request_reviews(pr.number)

    # Calculate expected review states
    reviews_by_user = github_reviews.group_by { |r| r.user.login }
    latest_actionable_reviews = reviews_by_user.map do |_user, reviews|
      actionable = reviews.reject { |r| r.state == "COMMENTED" }
      actionable.any? ? actionable.max_by(&:submitted_at) : reviews.max_by(&:submitted_at)
    end

    # Expected approved users
    expected_approved_users = latest_actionable_reviews
      .select { |r| r.state == "APPROVED" }
      .map { |r| r.user.login }
      .sort

    # Expected changes_requested users
    expected_changes_requested_users = latest_actionable_reviews
      .select { |r| r.state == "CHANGES_REQUESTED" }
      .map { |r| r.user.login }
      .sort

    # Stored approved users from approval_summary
    stored_approved_users = (pr.approval_summary&.dig(:approved_users) || []).sort
    stored_changes_requested_users = (pr.approval_summary&.dig(:changes_requested_users) || []).sort

    # Check for approval mismatches
    if stored_approved_users != expected_approved_users
      issues << "Approved users mismatch: stored=#{stored_approved_users}, expected=#{expected_approved_users}"
    end

    if stored_changes_requested_users != expected_changes_requested_users
      issues << "Changes requested users mismatch: stored=#{stored_changes_requested_users}, expected=#{expected_changes_requested_users}"
    end

    # Check backend approval status
    expected_backend_approved = (expected_approved_users & backend_members).any?
    expected_backend_status = expected_backend_approved ? "approved" : "not_approved"

    if pr.backend_approval_status != expected_backend_status
      issues << "Backend approval status mismatch: stored=#{pr.backend_approval_status}, expected=#{expected_backend_status}"
    end

    # === VERIFY STALE APPROVAL (commits after backend approval) ===
    # This catches the case where backend approved but author pushed new commits
    if pr.backend_approval_status == "approved"
      begin
        # Get the last backend approval timestamp
        last_backend_approval = latest_actionable_reviews
          .select { |r| r.state == "APPROVED" && backend_members.include?(r.user.login) }
          .max_by(&:submitted_at)

        if last_backend_approval
          # Fetch commits from GitHub
          commits = github_service.pull_request_commits(pr.number)

          # Check if any commits happened after the backend approval
          commits_after_approval = commits.select do |commit|
            commit_date = commit.commit.author.date rescue nil
            commit_date && commit_date > last_backend_approval.submitted_at
          end

          if commits_after_approval.any?
            issues << "STALE APPROVAL: Backend approved by #{last_backend_approval.user.login} at #{last_backend_approval.submitted_at}, but #{commits_after_approval.count} commit(s) pushed after"
          end
        end
      rescue => e
        Rails.logger.warn "[VerifyPrAccuracyJob] Could not verify commits after approval for PR ##{pr.number}: #{e.message}"
      end
    end

    # === VERIFY CI STATUS ===
    begin
      ci_result = hybrid_checker.get_accurate_pr_checks(pr)

      expected_ci_status = ci_result[:overall_status] || "unknown"
      expected_failed_checks = ci_result[:failed_checks] || 0
      expected_successful_checks = ci_result[:successful_checks] || 0
      expected_total_checks = ci_result[:total_checks] || 0

      # Allow some tolerance for CI status since checks can change rapidly
      if pr.ci_status != expected_ci_status && !(pr.ci_status == "pending" && expected_ci_status == "success")
        # Only flag if it's a meaningful difference (not just timing)
        if (pr.ci_status == "success" && expected_ci_status == "failure") ||
           (pr.ci_status == "failure" && expected_ci_status == "success")
          issues << "CI status mismatch: stored=#{pr.ci_status}, expected=#{expected_ci_status}"
        end
      end

      # Check failed checks count (significant discrepancies only)
      if (pr.failed_checks.to_i - expected_failed_checks).abs > 2
        issues << "Failed checks mismatch: stored=#{pr.failed_checks}, expected=#{expected_failed_checks}"
      end
    rescue => e
      Rails.logger.warn "[VerifyPrAccuracyJob] Could not verify CI for PR ##{pr.number}: #{e.message}"
    end

    {
      pr_number: pr.number,
      has_discrepancy: issues.any?,
      issues: issues,
      details: {
        stored: {
          backend_approval_status: pr.backend_approval_status,
          approved_users: stored_approved_users,
          changes_requested_users: stored_changes_requested_users,
          ci_status: pr.ci_status,
          failed_checks: pr.failed_checks
        },
        expected: {
          backend_approval_status: expected_backend_status,
          approved_users: expected_approved_users,
          changes_requested_users: expected_changes_requested_users,
          ci_status: expected_ci_status,
          failed_checks: expected_failed_checks
        }
      }
    }
  end

  def fix_pr_data(pr, github_service, hybrid_checker)
    Rails.logger.info "[VerifyPrAccuracyJob] Fixing PR ##{pr.number}..."

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

    # Refetch CI status
    begin
      ci_result = hybrid_checker.get_accurate_pr_checks(pr)

      pr.update!(
        ci_status: ci_result[:overall_status] || "unknown",
        total_checks: ci_result[:total_checks] || 0,
        successful_checks: ci_result[:successful_checks] || 0,
        failed_checks: ci_result[:failed_checks] || 0,
        pending_checks: ci_result[:pending_checks] || 0
      )

      # Update check runs
      if ci_result[:checks].any?
        pr.check_runs.destroy_all
        check_runs_data = ci_result[:checks].map do |check|
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
        CheckRun.insert_all(check_runs_data) if check_runs_data.any?
      end
    rescue => e
      Rails.logger.error "[VerifyPrAccuracyJob] Error fixing CI for PR ##{pr.number}: #{e.message}"
    end

    # Recalculate all statuses
    pr.update_backend_approval_status!
    pr.update_ready_for_backend_review!
    pr.update_approval_status!
    pr.update_awaiting_author_changes!

    Rails.logger.info "[VerifyPrAccuracyJob] Fixed PR ##{pr.number}: backend_status=#{pr.backend_approval_status}, ci_status=#{pr.ci_status}"
  end
end

class FetchAllPullRequestsJob < ApplicationJob
  queue_as :default

  def perform(repository_name: nil, repository_owner: nil, deep_verification: false)
    Rails.logger.info "[FetchAllPullRequestsJob] Starting full PR update for #{repository_owner}/#{repository_name || 'default'} (deep_verification: #{deep_verification})"

    github_service = GithubService.new(owner: repository_owner, repo: repository_name)

    # Check rate limit
    rate_limit = github_service.rate_limit
    if rate_limit.remaining < 100
      Rails.logger.warn "[FetchAllPullRequestsJob] Low API rate limit (#{rate_limit.remaining}), skipping"
      return
    end

    # Fetch all open PRs
    open_prs = github_service.all_pull_requests(state: "open")
    Rails.logger.info "[FetchAllPullRequestsJob] Found #{open_prs.count} open PRs"

    # Filter to only include PRs targeting master branch
    master_prs = open_prs.select { |pr| pr.base.ref == "master" }
    Rails.logger.info "[FetchAllPullRequestsJob] Filtered to #{master_prs.count} PRs targeting master branch"

    # Process PRs in smaller batches to avoid memory spikes (reduced from 10 to 3)
    master_prs.each_slice(3) do |batch|
      batch.each do |pr_data|
      # Find by github_id to avoid duplicate key violations
      pr = PullRequest.find_or_initialize_by(github_id: pr_data.id)

      # Set repository info if it's a new record
      if pr.new_record?
        pr.repository_name = repository_name || ENV["GITHUB_REPO"]
        pr.repository_owner = repository_owner || ENV["GITHUB_OWNER"]
      end

      pr.update!(
        github_id: pr_data.id,
        number: pr_data.number,
        title: pr_data.title,
        author: pr_data.user.login,
        state: pr_data.state,
        url: pr_data.html_url,
        pr_created_at: pr_data.created_at,
        pr_updated_at: pr_data.updated_at,
        draft: pr_data.draft || false,
        repository_name: repository_name || ENV["GITHUB_REPO"],
        repository_owner: repository_owner || ENV["GITHUB_OWNER"],
        labels: pr_data.labels.map(&:name),
        head_sha: pr_data.head.sha
      )

        # Skip comments fetching entirely - not used by dashboard
        # Comments consume memory and aren't displayed anywhere

        # Fetch checks inline for dashboard display
        # Skip delay to speed up processing
        fetch_pr_checks_inline(pr)
      end

      # Force garbage collection after each batch to free memory
      GC.start(full_mark: false, immediate_sweep: true)
    end

    # CRITICAL: Update merged/closed PRs on EVERY run (not just deep verification)
    # This ensures merged PRs are removed from the board within 30 minutes instead of 24 hours
    Rails.logger.info "[FetchAllPullRequestsJob] Checking for merged/closed PRs"
    scope = PullRequest.where(state: "open")
    scope = scope.where(repository_name: repository_name || ENV["GITHUB_REPO"])
    scope = scope.where(repository_owner: repository_owner || ENV["GITHUB_OWNER"])

    # Find PRs that are marked "open" in DB but not in GitHub's open list
    stale_pr_numbers = scope.where.not(number: master_prs.map(&:number)).pluck(:number)

    if stale_pr_numbers.any?
      Rails.logger.info "[FetchAllPullRequestsJob] Found #{stale_pr_numbers.count} potentially merged/closed PRs: #{stale_pr_numbers.inspect}"

      stale_pr_numbers.each do |pr_number|
        begin
          actual_pr = github_service.pull_request(pr_number)
          pr_record = scope.find_by(number: pr_number)
          if pr_record
            new_state = actual_pr.merged ? "merged" : "closed"
            Rails.logger.info "[FetchAllPullRequestsJob] Updating PR ##{pr_number} from 'open' to '#{new_state}'"
            pr_record.update!(state: new_state)
          end
        rescue Octokit::NotFound
          pr_record = scope.find_by(number: pr_number)
          pr_record&.destroy
          Rails.logger.info "[FetchAllPullRequestsJob] Deleted PR ##{pr_number} (not found on GitHub)"
        rescue => e
          Rails.logger.error "[FetchAllPullRequestsJob] Error updating PR ##{pr_number}: #{e.message}"
        end

        # Small delay to avoid rate limiting
        sleep 0.2
      end
    end

    # SKIP deep verification entirely during regular runs to minimize memory usage
    # Deep verification (HTML scraping, review re-verification) is VERY memory-intensive
    # Only run once per day at 1 AM when traffic is low
    if deep_verification
      Rails.logger.info "[FetchAllPullRequestsJob] Running deep verification (review verification, HTML scraping)"

      # Verify PRs in "PRs Needing Team Review" for API lag issues
      # Process in smaller batches (5 -> 3) to reduce memory
      verify_prs_needing_review(github_service, repository_name, repository_owner)

      # Web scraping verification as final check
      # SKIP THIS - most memory-intensive operation
      # verify_prs_via_html_scraping(repository_name, repository_owner)
      Rails.logger.info "[FetchAllPullRequestsJob] Skipping HTML scraping to minimize memory usage"
    else
      Rails.logger.info "[FetchAllPullRequestsJob] Skipping deep verification to minimize memory usage"
    end

    Rails.logger.info "[FetchAllPullRequestsJob] Completed full PR update"

  rescue => e
    Rails.logger.error "[FetchAllPullRequestsJob] Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def verify_prs_needing_review(github_service, repository_name, repository_owner)
    Rails.logger.info "[FetchAllPullRequestsJob] Verifying PRs Needing Team Review for API lag..."

    backend_reviewers = BackendReviewGroupMember.pluck(:username)

    # Use database queries instead of loading all PRs into memory
    # Only fetch IDs first, then process in batches
    needs_review_pr_ids = PullRequest.where(
      state: "open",
      repository_name: repository_name || ENV["GITHUB_REPO"],
      repository_owner: repository_owner || ENV["GITHUB_OWNER"]
    )
    .where.not(backend_approval_status: "approved")
    .where(draft: false)
    .pluck(:id)

    Rails.logger.info "[FetchAllPullRequestsJob] Found #{needs_review_pr_ids.count} potential PRs to verify"

    updated_count = 0

    # Process in batches of 3 to minimize memory usage (reduced from 5)
    needs_review_pr_ids.each_slice(3) do |batch_ids|
      PullRequest.where(id: batch_ids).each do |pr|
        # Skip if truly exempt or already has approvals
        next if pr.truly_exempt_from_backend_review?
        next if pr.approval_summary && pr.approval_summary[:approved_count].to_i > 0
        next if pr.approval_summary && pr.approval_summary[:approved_users]&.any? { |user| backend_reviewers.include?(user) }
      begin
        # Delete existing reviews to force fresh fetch
        pr.pull_request_reviews.destroy_all

        # Fetch fresh reviews from GitHub
        reviews = github_service.pull_request_reviews(pr.number)

        # Create reviews in database
        reviews.each do |review_data|
          PullRequestReview.create!(
            pull_request_id: pr.id,
            github_id: review_data.id,
            user: review_data.user.login,
            state: review_data.state,
            submitted_at: review_data.submitted_at
          )
        end

        # Store old status to check if it changed
        old_status = pr.backend_approval_status

        # Update approval statuses
        pr.update_backend_approval_status!
        pr.update_ready_for_backend_review!
        pr.update_approval_status!

        # Log if status changed
        if pr.backend_approval_status != old_status
          updated_count += 1
          Rails.logger.info "[FetchAllPullRequestsJob] PR ##{pr.number} status updated: #{old_status} -> #{pr.backend_approval_status}"
        end

        # Small delay to avoid rate limiting
        sleep 0.3

      rescue => e
        Rails.logger.error "[FetchAllPullRequestsJob] Error verifying PR ##{pr.number}: #{e.message}"
      end
      end

      # Force garbage collection after each batch
      GC.start(full_mark: false, immediate_sweep: true)
    end

    Rails.logger.info "[FetchAllPullRequestsJob] Verification complete. Updated #{updated_count} PRs"
  end

  def verify_prs_via_html_scraping(repository_name, repository_owner)
    Rails.logger.info "[FetchAllPullRequestsJob] Starting HTML scraping verification..."

    scraper = PrHtmlScraperService.new
    result = scraper.verify_prs_needing_review_via_html(repository_name, repository_owner)

    Rails.logger.info "[FetchAllPullRequestsJob] HTML scraping complete. Checked: #{result[:total_checked]}, Updated: #{result[:updated]}"

  rescue => e
    Rails.logger.error "[FetchAllPullRequestsJob] HTML scraping error: #{e.message}"
  end

  def fetch_pr_checks_inline(pr)
    # Use HybridPrCheckerService for faster API-based check fetching
    @hybrid_service ||= HybridPrCheckerService.new
    result = @hybrid_service.get_accurate_pr_checks(pr)

    # Update PR with check counts
    pr.update!(
      ci_status: result[:overall_status] || "unknown",
      total_checks: result[:total_checks] || 0,
      successful_checks: result[:successful_checks] || 0,
      failed_checks: result[:failed_checks] || 0,
      pending_checks: result[:pending_checks] || 0
    )

    # Store failing checks in cache for frontend
    if result[:failed_checks] > 0 && result[:checks].any?
      failing_checks = result[:checks].select { |c| [ "failure", "error", "cancelled", "pending" ].include?(c[:status]) }
      Rails.cache.write("pr_#{pr.id}_failing_checks", failing_checks, expires_in: 1.hour)
    else
      Rails.cache.delete("pr_#{pr.id}_failing_checks")
    end

    # Use upsert for check runs to avoid destroy_all + create! which is slow
    # Only store checks if there are failures or if this is first time seeing them
    if result[:checks].any? && (result[:failed_checks] > 0 || pr.check_runs.empty?)
      pr.check_runs.destroy_all
      check_runs_data = result[:checks].map do |check|
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

    # Check for commits after backend approval
    # This pre-populates the cache so the frontend doesn't need to make API calls
    if pr.backend_approval_status == "approved"
      begin
        # This will check and cache the result
        pr.has_commits_after_backend_approval?
        Rails.logger.info "[FetchAllPullRequestsJob] Checked commits after approval for PR ##{pr.number}"
      rescue => e
        Rails.logger.error "[FetchAllPullRequestsJob] Error checking commits after approval for PR ##{pr.number}: #{e.message}"
      end
    end

    # Update ready for backend review status
    pr.update_ready_for_backend_review!

    # Update approval status
    pr.update_approval_status!

  rescue => e
    Rails.logger.error "[FetchAllPullRequestsJob] Error fetching checks for PR ##{pr.number}: #{e.message}"
  end
end

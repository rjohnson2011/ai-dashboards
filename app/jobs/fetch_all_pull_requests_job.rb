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

    # Process PRs in batches to avoid memory spikes
    master_prs.each_slice(10) do |batch|
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

        # Only fetch comments during deep verification to save memory
        if deep_verification
          begin
            comments = github_service.pull_request_comments(pr_data.number)
            comments.each do |comment_data|
              PullRequestComment.find_or_create_by(github_id: comment_data.id) do |comment|
                comment.pull_request = pr
                comment.user = comment_data.user.login
                comment.body = comment_data.body
                comment.commented_at = comment_data.created_at
              end
            end
          rescue => e
            Rails.logger.error "[FetchAllPullRequestsJob] Error fetching comments for PR ##{pr_data.number}: #{e.message}"
          end
        end

        # Queue job to fetch checks
        FetchPullRequestChecksJob.perform_later(pr.id, repository_name: repository_name, repository_owner: repository_owner)
      end

      # Force garbage collection after each batch to free memory
      GC.start(full_mark: false, immediate_sweep: true)
    end

    # Only do expensive operations if deep_verification is true
    # This includes checking closed/merged PRs, re-verifying reviews, and HTML scraping
    # These operations should only run once or twice per day to minimize memory usage
    if deep_verification
      Rails.logger.info "[FetchAllPullRequestsJob] Running deep verification (closed PRs, reviews, HTML scraping)"

      # Clean up closed/merged PRs for this repository
      scope = PullRequest.where(state: "open")
      scope = scope.where(repository_name: repository_name || ENV["GITHUB_REPO"])
      scope = scope.where(repository_owner: repository_owner || ENV["GITHUB_OWNER"])
      scope.where.not(number: master_prs.map(&:number)).each do |pr|
        begin
          actual_pr = github_service.pull_request(pr.number)
          pr.update!(state: actual_pr.merged ? "merged" : "closed")
        rescue Octokit::NotFound
          pr.destroy
        end
      end

      # Verify PRs in "PRs Needing Team Review" for API lag issues
      verify_prs_needing_review(github_service, repository_name, repository_owner)

      # Web scraping verification as final check
      verify_prs_via_html_scraping(repository_name, repository_owner)
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

    # Process in batches of 5 to minimize memory usage
    needs_review_pr_ids.each_slice(5) do |batch_ids|
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
end

class Api::V1::ReviewsController < ApplicationController
  def index
    begin
      # Get repository parameters
      repository_name = params[:repository_name]
      repository_owner = params[:repository_owner]

      # Cache key includes repo and current hour to balance freshness with performance
      cache_key = "reviews_index:#{repository_owner}:#{repository_name}:#{Time.current.hour}"

      # Cache for 1 hour - balances memory usage with data freshness
      cached_data = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        # Check if repository columns exist (for backwards compatibility)
        has_repository_columns = PullRequest.column_names.include?("repository_name")

        # Build query scope
        if repository_name && repository_owner && has_repository_columns
          # Specific repository requested
          base_scope = PullRequest.where(repository_name: repository_name, repository_owner: repository_owner)
        elsif has_repository_columns
          # No specific repo requested - return all repositories
          base_scope = PullRequest.all
        else
          # Fallback for databases without repository columns
          base_scope = PullRequest
        end

        # Fetch open PRs WITHOUT eager loading to reduce memory usage
        # We'll load associations selectively only for data we actually use
        open_pull_requests = base_scope.open
          .where(backend_approval_status: "not_approved")
          .order(pr_updated_at: :desc)
          .limit(150) # Cap at 150 PRs to prevent memory issues

        # Fetch backend approved PRs separately
        approved_pull_requests = base_scope.open
          .where(backend_approval_status: "approved")
          .order(pr_updated_at: :desc)
          .limit(100) # Cap at 100 approved PRs

        # Check if this is a non-vets-api repository that needs on-demand scraping
        if has_repository_columns && repository_name != "vets-api" && base_scope.count == 0
          # Check if we've already started scraping recently
          scraping_key = "scraping_#{repository_owner}_#{repository_name}"
          unless Rails.cache.read(scraping_key)
            Rails.cache.write(scraping_key, true, expires_in: 5.minutes)
            # Trigger on-demand scraping for this repository
            FetchAllPullRequestsJob.perform_later(
              repository_name: repository_name,
              repository_owner: repository_owner
            )
          end
        end

        # If no PRs in database, return empty response
        if open_pull_requests.empty? && approved_pull_requests.empty?
          return {
            pull_requests: [],
            approved_pull_requests: [],
            count: 0,
            approved_count: 0,
            repository: repository_name && repository_owner ? "#{repository_owner}/#{repository_name}" : "All repositories",
            message: repository_name == "vets-api" ?
              "Data is being refreshed. Please check back in a few minutes." :
              "Loading data for #{repository_name}. This may take a few minutes for the first load.",
            last_updated: nil,
            updating: true
          }
        end

        # Batch load ALL failing check runs for all PRs at once to avoid N+1 queries
        all_pr_ids = (open_pull_requests.pluck(:id) + approved_pull_requests.pluck(:id)).uniq
        failing_checks_by_pr = CheckRun
          .where(pull_request_id: all_pr_ids)
          .where(status: [ "failure", "error", "cancelled" ])
          .select(:pull_request_id, :suite_name, :name, :status, :url, :description, :required)
          .group_by(&:pull_request_id)

        # Format PR data helper - uses pre-loaded failing checks
        format_pr = lambda do |pr|
          # Use pre-loaded failing checks grouped by PR ID
          pr_failing_checks = failing_checks_by_pr[pr.id] || []
          failing_checks = pr_failing_checks.map do |check|
            {
              name: check.suite_name || check.name,
              status: check.status,
              url: check.url,
              description: check.description,
              required: check.required
            }
          end.uniq { |c| c[:name] } # Deduplicate by name

        # Create simple timeline from existing data to avoid API calls
        timeline_data = []

        # Add last update
        if pr.pr_updated_at
          time_ago = time_ago_in_words(pr.pr_updated_at)
          timeline_data << "Updated #{time_ago}"
        end

        # Add backend approval status
        if pr.backend_approval_status == "approved"
          timeline_data << "Backend approved ✅"
        elsif pr.ready_for_backend_review
          timeline_data << "Ready for backend review 👀"
        end

        # Add CI status
        if pr.ci_status == "failure" && pr.failed_checks > 0
          timeline_data << "#{pr.failed_checks} CI checks failing ❌"
        elsif pr.ci_status == "success"
          timeline_data << "All CI checks passing ✅"
        elsif pr.pending_checks && pr.pending_checks > 0
          timeline_data << "#{pr.pending_checks} checks pending ⏳"
        end

        # Add review status
        if pr.approval_summary
          if pr.approval_summary[:approved_count] > 0
            timeline_data << "#{pr.approval_summary[:approved_count]} approvals 👍"
          end
          if pr.approval_summary[:changes_requested_count] > 0
            timeline_data << "Changes requested 🔄"
          end
        end

        # Add draft status
        if pr.draft
          timeline_data << "Draft PR 📝"
        end

        {
          id: pr.github_id,
          number: pr.number,
          title: pr.title,
          author: pr.author,
          created_at: pr.pr_created_at,
          updated_at: pr.pr_updated_at,
          url: pr.url,
          state: pr.state,
          draft: pr.draft,
          mergeable: nil, # Not scraped from web
          additions: nil, # Not scraped from web
          deletions: nil, # Not scraped from web
          changed_files: nil, # Not scraped from web
          ci_status: pr.ci_status || "pending",
          failing_checks: failing_checks,
          total_checks: pr.total_checks,
          successful_checks: pr.successful_checks,
          failed_checks: pr.failed_checks,
          backend_approval_status: pr.backend_approval_status,
          approval_summary: pr.approval_summary,
          ready_for_backend_review: pr.ready_for_backend_review,
          recent_timeline: timeline_data,
          labels: pr.labels || [],
          repository_name: pr.repository_name,
          repository_owner: pr.repository_owner,
          changes_requested_info: pr.changes_requested_info
        }
      end

        # Format both sets of PRs
        open_pr_data = open_pull_requests.map(&format_pr)
        approved_pr_data = approved_pull_requests.map(&format_pr)

        # Get the most recent PR update time
        recent_pr_update = if repository_name && repository_owner
          PullRequest
            .where(repository_owner: repository_owner, repository_name: repository_name)
            .maximum(:updated_at)
        else
          PullRequest.maximum(:updated_at)
        end

        # Return formatted data to be cached
        {
          pull_requests: open_pr_data,
          approved_pull_requests: approved_pr_data,
          count: open_pr_data.length,
          approved_count: approved_pr_data.length,
          repository: repository_name && repository_owner ? "#{repository_owner}/#{repository_name}" : "All repositories",
          last_updated: recent_pr_update || Time.current
        }
      end # End of cache block

      # Get rate limit info (not cached - always fresh)
      github_service = GithubService.new(owner: repository_owner, repo: repository_name)
      rate_limit_info = github_service.rate_limit rescue nil

      # Check if actually updating (not cached - always fresh)
      refresh_status = Rails.cache.read("refresh_status") || {}
      is_updating = refresh_status[:updating] || false

      # Merge cached data with fresh status info
      render json: cached_data.merge({
        updating: is_updating,
        rate_limit: rate_limit_info ? {
          remaining: rate_limit_info.remaining,
          limit: rate_limit_info.limit,
          resets_at: rate_limit_info.resets_at
        } : nil,
        api_calls_used: 0
      })
    rescue => e
      Rails.logger.error "Error fetching PRs: #{e.message}"
      render json: { error: "Failed to fetch pull requests" }, status: :internal_server_error
    end
  end

  def status
    begin
      # Simple status check - assume we're always updating if the data is recent
      last_updated = PullRequest.maximum(:updated_at)
      total_prs = PullRequest.open.count

      # Check if a refresh job is currently running
      refresh_status = Rails.cache.read("refresh_status") || {}

      render json: {
        updating: refresh_status[:updating] || false,
        last_updated: last_updated,
        total_prs: total_prs,
        progress: refresh_status[:progress] || { current: 0, total: 0 }
      }
    rescue => e
      Rails.logger.error "Error checking status: #{e.message}"
      render json: { error: "Failed to check status" }, status: :internal_server_error
    end
  end

  def refresh
    begin
      # Trigger background refresh job
      FetchAllPullRequestsJob.perform_later

      render json: { message: "Refresh started" }
    rescue => e
      Rails.logger.error "Error starting refresh: #{e.message}"
      render json: { error: "Failed to start refresh" }, status: :internal_server_error
    end
  end

  def version
    begin
      # Get git commit hash
      git_commit = `git rev-parse HEAD 2>/dev/null`.strip rescue "unknown"
      git_branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip rescue "unknown"

      render json: {
        status: "ok",
        version: "1.0.0",
        git_commit: git_commit[0..7],
        git_commit_full: git_commit,
        git_branch: git_branch,
        rails_version: Rails.version,
        ruby_version: RUBY_VERSION,
        environment: Rails.env,
        deployed_at: Time.current,
        services: {
          hybrid_pr_checker: defined?(HybridPrCheckerService).present?,
          github_service: defined?(GithubService).present?,
          fetch_all_prs_job: defined?(FetchAllPullRequestsJob).present?
        }
      }
    rescue => e
      Rails.logger.error "Error getting version: #{e.message}"
      render json: { error: "Failed to get version" }, status: :internal_server_error
    end
  end

  def show
    repository_name = params[:repository_name] || ENV["GITHUB_REPO"]
    repository_owner = params[:repository_owner] || ENV["GITHUB_OWNER"]

    github_service = GithubService.new(owner: repository_owner, repo: repository_name)
    pr_number = params[:number]

    begin
      pr_with_reviews = github_service.pull_request_with_reviews(pr_number)

      if pr_with_reviews
        render json: {
          pull_request: format_pr(pr_with_reviews[:pr]),
          reviews: format_reviews(pr_with_reviews[:reviews])
        }
      else
        render json: { error: "Pull request not found" }, status: :not_found
      end
    rescue => e
      Rails.logger.error "Error fetching PR #{pr_number}: #{e.message}"
      render json: { error: "Failed to fetch pull request" }, status: :internal_server_error
    end
  end

  def timeline
    begin
      pr_number = params[:number]&.to_i
      repository_name = params[:repository_name] || ENV["GITHUB_REPO"]
      repository_owner = params[:repository_owner] || ENV["GITHUB_OWNER"]

      unless pr_number && pr_number > 0
        return render json: { error: "Invalid PR number" }, status: :bad_request
      end

      timeline_service = PrTimelineService.new(owner: repository_owner, repo: repository_name)
      timeline_data = timeline_service.get_recent_timeline(pr_number, 5)

      render json: {
        pr_number: pr_number,
        timeline: timeline_data
      }
    rescue => e
      Rails.logger.error "Error fetching timeline for PR #{pr_number}: #{e.message}"
      render json: { error: "Failed to fetch timeline" }, status: :internal_server_error
    end
  end

  def historical
    begin
      # Get the number of days from params, default to 30
      days = params[:days]&.to_i || 30

      # Get repository parameters
      repository_name = params[:repository_name] || ENV["GITHUB_REPO"]
      repository_owner = params[:repository_owner] || ENV["GITHUB_OWNER"]

      # Check if repository columns exist in DailySnapshot
      has_repository_columns = DailySnapshot.column_names.include?("repository_name")

      # Get historical snapshots for this repository
      if has_repository_columns
        snapshots = DailySnapshot.last_n_days(days, repository_name: repository_name, repository_owner: repository_owner)
      else
        # Fallback for databases without repository columns
        snapshots = DailySnapshot.last_n_days(days)
      end

      # Format data for the chart
      chart_data = snapshots.map do |snapshot|
        {
          date: snapshot.snapshot_date.to_s,
          total_prs: snapshot.total_prs,
          approved_prs: snapshot.approved_prs,
          pending_review_prs: snapshot.pending_review_prs,
          changes_requested_prs: snapshot.prs_with_changes_requested,
          draft_prs: snapshot.draft_prs,
          failing_ci_prs: snapshot.failing_ci_prs,
          successful_ci_prs: snapshot.successful_ci_prs,
          prs_opened_today: snapshot.prs_opened_today || 0,
          prs_closed_today: snapshot.prs_closed_today || 0,
          prs_merged_today: snapshot.prs_merged_today || 0
        }
      end

      render json: {
        data: chart_data,
        period: "#{days} days",
        start_date: days.days.ago.to_date.to_s,
        end_date: Date.current.to_s
      }
    rescue => e
      Rails.logger.error "Error fetching historical data: #{e.message}"
      render json: { error: "Failed to fetch historical data" }, status: :internal_server_error
    end
  end

  private

  def time_ago_in_words(time)
    return "unknown" unless time

    seconds = Time.now - time
    case seconds
    when 0...60
      "just now"
    when 60...3600
      "#{(seconds / 60).round}m ago"
    when 3600...86400
      "#{(seconds / 3600).round}h ago"
    when 86400...604800
      "#{(seconds / 86400).round}d ago"
    else
      time.strftime("%b %d")
    end
  end

  def format_pr(pr)
    {
      id: pr.id,
      number: pr.number,
      title: pr.title,
      author: pr.user.login,
      created_at: pr.created_at,
      updated_at: pr.updated_at,
      url: pr.html_url,
      state: pr.state,
      draft: pr.draft,
      mergeable: pr.mergeable,
      additions: pr.additions,
      deletions: pr.deletions,
      changed_files: pr.changed_files,
      body: pr.body
    }
  end

  def format_reviews(reviews)
    reviews.map do |review|
      {
        id: review.id,
        user: review.user.login,
        state: review.state,
        body: review.body,
        submitted_at: review.submitted_at,
        html_url: review.html_url
      }
    end
  end
end

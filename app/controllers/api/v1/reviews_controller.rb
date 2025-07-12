class Api::V1::ReviewsController < ApplicationController
  def index
    begin
      # Fetch all open PRs from database
      pull_requests = PullRequest.open.includes(:check_runs).order(pr_updated_at: :desc)
      
      # Always trigger background job to refresh data in real-time
      FetchPullRequestDataJob.perform_later
      
      # If no PRs in database, return empty response with message
      if pull_requests.empty?
        return render json: { 
          pull_requests: [],
          count: 0,
          repository: "#{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']}",
          message: "Data is being refreshed. Please check back in a few minutes.",
          last_updated: nil,
          updating: true
        }
      end
      
      # Format PR data
      pr_data = pull_requests.map do |pr|
        failing_checks = pr.check_runs.failed.deduplicate_by_suite.map do |check|
          {
            name: check.suite_name || check.name,
            status: check.status,
            url: check.url,
            description: check.description,
            required: check.required
          }
        end
        
        # Find the backend approval check
        backend_approval_check = pr.check_runs.find { |check| 
          check.name&.include?('Succeed if backend approval is confirmed') 
        }
        
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
          ci_status: pr.overall_status,
          failing_checks: failing_checks,
          total_checks: pr.total_checks,
          successful_checks: pr.successful_checks,
          failed_checks: pr.failed_checks,
          backend_approval_status: backend_approval_check ? 
            (backend_approval_check.status == 'unknown' ? 'skipped' : backend_approval_check.status) : 
            'not_applicable'
        }
      end
      
      # Get rate limit info
      github_service = GithubService.new
      rate_limit_info = github_service.rate_limit rescue nil
      
      # Get the actual refresh completion time
      last_refresh_time = Rails.cache.read('last_refresh_time') || pull_requests.maximum(:updated_at)
      
      render json: { 
        pull_requests: pr_data,
        count: pr_data.length,
        repository: "#{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']}",
        last_updated: last_refresh_time,
        updating: true,
        rate_limit: rate_limit_info ? {
          remaining: rate_limit_info.remaining,
          limit: rate_limit_info.limit,
          resets_at: rate_limit_info.resets_at
        } : nil,
        api_calls_used: 0
      }
    rescue => e
      Rails.logger.error "Error fetching PRs: #{e.message}"
      render json: { error: 'Failed to fetch pull requests' }, status: :internal_server_error
    end
  end

  def status
    begin
      # Simple status check - assume we're always updating if the data is recent
      last_updated = PullRequest.maximum(:updated_at)
      total_prs = PullRequest.open.count
      
      # Check if a refresh job is currently running
      refresh_status = Rails.cache.read('refresh_status') || {}
      
      render json: {
        updating: refresh_status[:updating] || false,
        last_updated: last_updated,
        total_prs: total_prs,
        progress: refresh_status[:progress] || { current: 0, total: 0 }
      }
    rescue => e
      Rails.logger.error "Error checking status: #{e.message}"
      render json: { error: 'Failed to check status' }, status: :internal_server_error
    end
  end

  def refresh
    begin
      # Trigger background refresh job
      FetchPullRequestDataJob.perform_later
      
      render json: { message: 'Refresh started' }
    rescue => e
      Rails.logger.error "Error starting refresh: #{e.message}"
      render json: { error: 'Failed to start refresh' }, status: :internal_server_error
    end
  end

  def show
    github_service = GithubService.new
    pr_number = params[:number]
    
    begin
      pr_with_reviews = github_service.pull_request_with_reviews(pr_number)
      
      if pr_with_reviews
        render json: {
          pull_request: format_pr(pr_with_reviews[:pr]),
          reviews: format_reviews(pr_with_reviews[:reviews])
        }
      else
        render json: { error: 'Pull request not found' }, status: :not_found
      end
    rescue => e
      Rails.logger.error "Error fetching PR #{pr_number}: #{e.message}"
      render json: { error: 'Failed to fetch pull request' }, status: :internal_server_error
    end
  end

  private

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
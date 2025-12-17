class AdminController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_admin_token, except: [ :health ]

  def health
    render json: {
      status: "ok",
      version: ENV["RENDER_GIT_COMMIT"] || "unknown",
      timestamp: Time.current
    }
  end

  def verify_scraper_version
    # Check which service is being used for check fetching
    hybrid_service = HybridPrCheckerService.new

    # Get commit hash
    git_commit = `git rev-parse HEAD 2>/dev/null`.strip rescue "unknown"

    render json: {
      status: "ok",
      git_commit: git_commit[0..7],
      git_commit_full: git_commit,
      hybrid_pr_checker_exists: defined?(HybridPrCheckerService).present?,
      enhanced_scraper_exists: defined?(EnhancedGithubScraperService).present?,
      fetch_all_pull_requests_job_path: FetchAllPullRequestsJob.instance_method(:fetch_pr_checks_inline).source_location&.first,
      timestamp: Time.current
    }
  end

  def update_data
    repository_name = params[:repository_name] || ENV["GITHUB_REPO"]
    repository_owner = params[:repository_owner] || ENV["GITHUB_OWNER"]

    FetchAllPullRequestsJob.perform_now(
      repository_name: repository_name,
      repository_owner: repository_owner
    )

    render json: {
      status: "success",
      message: "Data updated successfully",
      repository: "#{repository_owner}/#{repository_name}"
    }
  rescue => e
    render json: {
      status: "error",
      message: e.message
    }, status: 500
  end

  private

  def verify_admin_token
    token = params[:token] || request.headers["Authorization"]&.gsub("Bearer ", "")

    unless token == ENV["ADMIN_TOKEN"]
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end

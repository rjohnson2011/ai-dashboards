class FetchAllPullRequestsJob < ApplicationJob
  queue_as :default

  def perform(repository_name: nil, repository_owner: nil)
    Rails.logger.info "[FetchAllPullRequestsJob] Starting full PR update for #{repository_owner}/#{repository_name || 'default'}"

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

    # Update or create PR records
    open_prs.each do |pr_data|
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

      # Queue job to fetch checks
      FetchPullRequestChecksJob.perform_later(pr.id, repository_name: repository_name, repository_owner: repository_owner)
    end

    # Clean up closed/merged PRs for this repository
    scope = PullRequest.where(state: "open")
    scope = scope.where(repository_name: repository_name || ENV["GITHUB_REPO"])
    scope = scope.where(repository_owner: repository_owner || ENV["GITHUB_OWNER"])
    scope.where.not(number: open_prs.map(&:number)).each do |pr|
      begin
        actual_pr = github_service.pull_request(pr.number)
        pr.update!(state: actual_pr.merged ? "merged" : "closed")
      rescue Octokit::NotFound
        pr.destroy
      end
    end

    Rails.logger.info "[FetchAllPullRequestsJob] Completed full PR update"

  rescue => e
    Rails.logger.error "[FetchAllPullRequestsJob] Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end

class GithubService
  def initialize
    @client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
    @owner = ENV['GITHUB_OWNER']
    @repo = ENV['GITHUB_REPO']
  end

  def pull_requests(state: 'open', per_page: 100)
    @client.pull_requests("#{@owner}/#{@repo}", state: state, per_page: per_page)
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error: #{e.message}"
    []
  end

  def all_pull_requests(state: 'open')
    all_prs = []
    page = 1
    
    loop do
      prs = @client.pull_requests("#{@owner}/#{@repo}", state: state, per_page: 100, page: page)
      break if prs.empty?
      
      all_prs.concat(prs)
      page += 1
      
      # Safety check to prevent infinite loops
      break if page > 10 # Max 1000 PRs
    end
    
    all_prs
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error: #{e.message}"
    []
  end

  def pull_request_reviews(pr_number)
    @client.pull_request_reviews("#{@owner}/#{@repo}", pr_number)
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error: #{e.message}"
    []
  end

  def pull_request_with_reviews(pr_number)
    pr = @client.pull_request("#{@owner}/#{@repo}", pr_number)
    reviews = pull_request_reviews(pr_number)
    
    {
      pr: pr,
      reviews: reviews
    }
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error: #{e.message}"
    nil
  end

  def rate_limit
    @client.rate_limit
  end

  def commit_status(sha)
    @client.combined_status("#{@owner}/#{@repo}", sha)
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error fetching commit status: #{e.message}"
    nil
  end

  def commit_statuses(sha)
    @client.statuses("#{@owner}/#{@repo}", sha)
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error fetching commit statuses: #{e.message}"
    []
  end

  def check_suites(sha)
    @client.check_suites("#{@owner}/#{@repo}", sha)
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error fetching check suites: #{e.message}"
    nil
  end

  def check_runs_for_suite(check_suite_id)
    @client.check_runs_for_suite("#{@owner}/#{@repo}", check_suite_id)
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error fetching check runs: #{e.message}"
    nil
  end

  def get_ci_status(pr)
    # Use web scraping to get CI status from the PR page
    scraper = GithubScraperService.new
    scraper.scrape_pr_checks(pr.html_url)
  rescue => e
    Rails.logger.error "Error getting CI status for PR: #{e.message}"
    {
      overall_status: 'error',
      failing_checks: [],
      total_checks: 0
    }
  end

  private

  def repository_path
    "#{@owner}/#{@repo}"
  end
end
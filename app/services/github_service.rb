require 'ostruct'

class GithubService
  def initialize(owner: nil, repo: nil)
    @client = Octokit::Client.new(access_token: ENV["GITHUB_TOKEN"])
    @owner = owner || ENV["GITHUB_OWNER"]
    @repo = repo || ENV["GITHUB_REPO"]
  end

  def pull_requests(state: "open", per_page: 100)
    @client.pull_requests("#{@owner}/#{@repo}", state: state, per_page: per_page)
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error: #{e.message}"
    []
  end

  def all_pull_requests(state: "open")
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

  def pull_request(pr_number)
    @client.pull_request("#{@owner}/#{@repo}", pr_number)
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error: #{e.message}"
    nil
  end

  def pull_request_reviews(pr_number)
    # Use GraphQL API for more accurate review data
    # The REST API doesn't always return the latest reviews
    graphql_reviews(pr_number)
  rescue => e
    Rails.logger.error "GitHub API Error fetching reviews: #{e.message}"
    # Fallback to REST API if GraphQL fails
    begin
      @client.pull_request_reviews("#{@owner}/#{@repo}", pr_number)
    rescue Octokit::Error => rest_error
      Rails.logger.error "GitHub REST API Error (fallback): #{rest_error.message}"
      []
    end
  end

  def graphql_reviews(pr_number)
    # Use GraphQL's latestReviews which provides the most recent review from each user
    # This is more accurate than the REST API's reviews endpoint
    query = <<~GRAPHQL
      query {
        repository(owner: "#{@owner}", name: "#{@repo}") {
          pullRequest(number: #{pr_number}) {
            reviewDecision
            latestReviews(last: 100) {
              nodes {
                author {
                  login
                }
                state
                submittedAt
                id
              }
            }
          }
        }
      }
    GRAPHQL

    result = @client.post('/graphql', { query: query }.to_json)

    if result && result[:data] && result[:data][:repository] && result[:data][:repository][:pullRequest]
      pr_data = result[:data][:repository][:pullRequest]
      reviews = pr_data[:latestReviews][:nodes]

      # Convert GraphQL format to match REST API format for compatibility
      reviews.map do |review|
        OpenStruct.new(
          id: review[:id].hash, # Convert GraphQL ID to numeric-like ID
          user: OpenStruct.new(login: review[:author][:login]),
          state: review[:state],
          submitted_at: Time.parse(review[:submittedAt])
        )
      end
    else
      Rails.logger.error "GraphQL query returned unexpected structure: #{result.inspect}"
      []
    end
  rescue => e
    Rails.logger.error "GraphQL Error fetching reviews: #{e.message}"
    raise e
  end

  def pull_request_comments(pr_number)
    # Note: In GitHub API, PR comments (issue comments) are different from review comments
    # This fetches issue comments (regular comments on the PR thread)
    @client.issue_comments("#{@owner}/#{@repo}", pr_number)
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error fetching PR comments: #{e.message}"
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

  def search_pull_requests(query:, per_page: 30)
    @client.search_issues(query, per_page: per_page)
  rescue Octokit::Error => e
    Rails.logger.error "GitHub API Error searching PRs: #{e.message}"
    OpenStruct.new(total_count: 0, items: [])
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
    scraper = GithubScraperService.new(owner: @owner, repo: @repo)
    scraper.scrape_pr_checks(pr.html_url)
  rescue => e
    Rails.logger.error "Error getting CI status for PR: #{e.message}"
    {
      overall_status: "error",
      failing_checks: [],
      total_checks: 0
    }
  end

  private

  def repository_path
    "#{@owner}/#{@repo}"
  end
end

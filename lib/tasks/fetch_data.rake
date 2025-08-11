namespace :data do
  desc "Fetch initial pull request data"
  task fetch_initial: :environment do
    puts "Starting initial data fetch..."

    # Clear any locks
    Rails.cache.delete("pull_request_data_updating")

    # Fetch GitHub PR data (fast)
    puts "Fetching PR data from GitHub API..."
    github_token = ENV["GITHUB_TOKEN"]
    owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
    repo = ENV["GITHUB_REPO"] || "vets-api"

    client = Octokit::Client.new(access_token: github_token)
    prs = client.pull_requests("#{owner}/#{repo}", state: "open", per_page: 100)

    puts "Found #{prs.count} pull requests"

    # Save basic PR data without checks (fast)
    prs.each do |pr_data|
      pr = PullRequest.find_or_initialize_by(number: pr_data[:number])
      pr.update!(
        github_id: pr_data[:id],
        title: pr_data[:title],
        author: pr_data[:user][:login],
        state: pr_data[:state],
        url: pr_data[:html_url],
        pr_created_at: pr_data[:created_at],
        pr_updated_at: pr_data[:updated_at],
        draft: pr_data[:draft] || false,
        ci_status: "pending",
        backend_approval_status: "not_approved",
        total_checks: 0,
        successful_checks: 0,
        failed_checks: 0
      )
    end

    puts "Initial data saved. PRs will show as 'pending' CI status."
    puts "Run 'rails data:fetch_checks' to update CI status (this will take longer)"
  end

  desc "Fetch CI checks for all PRs (slow)"
  task fetch_checks: :environment do
    puts "Fetching CI checks for all PRs..."
    PullRequest.find_each.with_index do |pr, index|
      print "\rProcessing PR #{index + 1}/#{PullRequest.count}..."

      begin
        scraper = EnhancedGithubScraperService.new
        check_data = scraper.fetch_check_runs(pr.number)

        pr.update!(
          ci_status: check_data[:status],
          failing_checks: check_data[:failing_checks],
          total_checks: check_data[:total_checks],
          successful_checks: check_data[:successful_checks],
          failed_checks: check_data[:failed_checks],
          scraped_at: Time.current
        )
      rescue => e
        puts "\nError fetching checks for PR ##{pr.number}: #{e.message}"
      end
    end

    puts "\nDone!"
  end
end

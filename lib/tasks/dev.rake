namespace :dev do
  desc "Run background jobs locally (simulates production scheduler)"
  task run_updates: :environment do
    puts "Running local updates..."

    # 1. Update PR data
    puts "\n1. Updating PR data..."
    Rake::Task["pr_update_data"].invoke

    # 2. Update checks via API
    puts "\n2. Updating PR checks via GitHub API..."
    service = GithubChecksApiService.new
    result = service.update_all_prs_with_checks
    puts "   Updated: #{result[:updated]} PRs, Errors: #{result[:errors]}"

    # 3. Update approval statuses
    puts "\n3. Updating approval statuses..."
    Rake::Task["pr:update_approval_status"].invoke

    # 4. Update last refresh time
    Rails.cache.write("last_refresh_time", Time.current)

    puts "\n✓ All updates complete!"
    puts "Last updated: #{Time.current}"
  end

  desc "Start local background job scheduler (runs every 15 minutes)"
  task scheduler: :environment do
    puts "Starting local scheduler - will run updates every 15 minutes"
    puts "Press Ctrl+C to stop"

    loop do
      puts "\n" + "="*60
      puts "Running scheduled update at #{Time.current}"
      puts "="*60

      Rake::Task["dev:run_updates"].invoke
      Rake::Task["dev:run_updates"].reenable

      puts "\nNext update in 15 minutes..."
      sleep(900) # 15 minutes
    end
  end

  desc "Quick update - just refresh PR data and checks"
  task quick_update: :environment do
    puts "Running quick update..."

    # Fetch new PRs
    github_token = ENV["GITHUB_TOKEN"]
    owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
    repo = ENV["GITHUB_REPO"] || "vets-api"

    client = Octokit::Client.new(access_token: github_token)
    prs = client.pull_requests("#{owner}/#{repo}", state: "open", per_page: 30)

    updated = 0
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
        draft: pr_data[:draft] || false
      )
      updated += 1
    end

    Rails.cache.write("last_refresh_time", Time.current)

    puts "Updated #{updated} PRs"
    puts "Last updated: #{Time.current}"
  end
end

# Helper task
task pr_update_data: :environment do
  github_token = ENV["GITHUB_TOKEN"]
  owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
  repo = ENV["GITHUB_REPO"] || "vets-api"

  client = Octokit::Client.new(access_token: github_token)

  # Cleanup merged/closed PRs first
  PullRequest.where(state: "open").find_each do |pr|
    begin
      github_pr = client.pull_request("#{owner}/#{repo}", pr.number)
      if github_pr.state == "closed"
        pr.update!(state: github_pr.merged ? "merged" : "closed")
      end
    rescue Octokit::NotFound
      pr.destroy
    rescue => e
      Rails.logger.error "Error checking PR ##{pr.number}: #{e.message}"
    end
  end

  # Fetch open PRs
  prs = client.pull_requests("#{owner}/#{repo}", state: "open", per_page: 100)

  new_count = 0
  updated_count = 0

  prs.each do |pr_data|
    pr = PullRequest.find_or_initialize_by(number: pr_data[:number])
    is_new = pr.new_record?

    pr.update!(
      github_id: pr_data[:id],
      title: pr_data[:title],
      author: pr_data[:user][:login],
      state: pr_data[:state],
      url: pr_data[:html_url],
      pr_created_at: pr_data[:created_at],
      pr_updated_at: pr_data[:updated_at],
      draft: pr_data[:draft] || false
    )

    if is_new
      new_count += 1
    else
      updated_count += 1
    end
  end

  # Fetch reviews for all PRs
  PullRequest.where(state: "open").find_each do |pr|
    begin
      reviews = client.pull_request_reviews("#{owner}/#{repo}", pr.number)
      reviews.each do |review_data|
        PullRequestReview.find_or_create_by(
          pull_request_id: pr.id,
          github_id: review_data[:id]
        ).update!(
          user: review_data[:user][:login],
          state: review_data[:state],
          submitted_at: review_data[:submitted_at]
        )
      end
      pr.update_backend_approval_status!
    rescue => e
      Rails.logger.error "Error fetching reviews for PR ##{pr.number}: #{e.message}"
    end
  end

  puts "New PRs: #{new_count}, Updated PRs: #{updated_count}"
end

namespace :admin do
  desc "Update all PRs with full data (CI status, reviews, etc)"
  task update_full_data: :environment do
    puts "Starting full data update..."
    updated_count = 0
    error_count = 0

    PullRequest.find_each do |pr|
      print "\rUpdating PR #{updated_count + error_count + 1}/#{PullRequest.count}..."

      begin
        # Fetch CI checks
        scraper = EnhancedGithubScraperService.new
        check_data = scraper.scrape_pr_checks_detailed(pr.url)

        pr.update!(
          ci_status: check_data[:overall_status] || "pending",
          total_checks: check_data[:total_checks] || 0,
          successful_checks: check_data[:successful_checks] || 0,
          failed_checks: check_data[:failed_checks] || 0
        )

        # Store failing checks in Rails cache
        if check_data[:checks] && check_data[:checks].any? { |c| c[:status] == "failure" }
          failing_checks = check_data[:checks].select { |c| c[:status] == "failure" }
          Rails.cache.write("pr_#{pr.id}_failing_checks", failing_checks, expires_in: 1.hour)
        end

        # Fetch reviews
        github_token = ENV["GITHUB_TOKEN"]
        owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
        repo = ENV["GITHUB_REPO"] || "vets-api"
        client = Octokit::Client.new(access_token: github_token)

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

        # Update backend approval
        pr.update_backend_approval_status!

        updated_count += 1
      rescue => e
        error_count += 1
        puts "\nError updating PR ##{pr.number}: #{e.message}"
      end
    end

    puts "\n\nUpdate completed!"
    puts "Successfully updated: #{updated_count}"
    puts "Errors: #{error_count}"
  end

  desc "Clean up merged/closed PRs"
  task cleanup_merged: :environment do
    puts "Checking for merged/closed PRs..."

    github_token = ENV["GITHUB_TOKEN"]
    owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
    repo = ENV["GITHUB_REPO"] || "vets-api"
    client = Octokit::Client.new(access_token: github_token)

    updated_count = 0
    deleted_count = 0

    PullRequest.where(state: "open").find_each do |pr|
      print "\rChecking PR ##{pr.number}..."

      begin
        github_pr = client.pull_request("#{owner}/#{repo}", pr.number)

        if github_pr.state == "closed"
          if github_pr.merged
            pr.update!(state: "merged")
            puts "\n  → PR ##{pr.number} marked as merged"
          else
            pr.update!(state: "closed")
            puts "\n  → PR ##{pr.number} marked as closed"
          end
          updated_count += 1
        end
      rescue Octokit::NotFound
        pr.destroy
        puts "\n  → PR ##{pr.number} deleted (not found on GitHub)"
        deleted_count += 1
      rescue => e
        puts "\n  ✗ Error checking PR ##{pr.number}: #{e.message}"
      end
    end

    puts "\n\nCleanup completed!"
    puts "Updated to merged/closed: #{updated_count}"
    puts "Deleted: #{deleted_count}"
    puts "Remaining open: #{PullRequest.where(state: 'open').count}"
  end

  desc "Update a single PR by number"
  task :update_pr, [ :number ] => :environment do |t, args|
    pr_number = args[:number].to_i
    pr = PullRequest.find_by(number: pr_number)

    if pr.nil?
      puts "PR ##{pr_number} not found in database"
      exit
    end

    puts "Updating PR ##{pr.number}: #{pr.title}"

    # Fetch CI checks
    scraper = EnhancedGithubScraperService.new
    check_data = scraper.scrape_pr_checks_detailed(pr.url)

    pr.update!(
      ci_status: check_data[:overall_status] || "pending",
      total_checks: check_data[:total_checks] || 0,
      successful_checks: check_data[:successful_checks] || 0,
      failed_checks: check_data[:failed_checks] || 0
    )

    # Store failing checks
    if check_data[:checks] && check_data[:checks].any? { |c| c[:status] == "failure" }
      failing_checks = check_data[:checks].select { |c| c[:status] == "failure" }
      Rails.cache.write("pr_#{pr.id}_failing_checks", failing_checks, expires_in: 1.hour)
    end

    # Fetch reviews
    github_token = ENV["GITHUB_TOKEN"]
    owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
    repo = ENV["GITHUB_REPO"] || "vets-api"
    client = Octokit::Client.new(access_token: github_token)

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

    # Update backend approval
    pr.update_backend_approval_status!

    puts "\nUpdate complete!"
    puts "CI Status: #{pr.ci_status}"
    puts "Checks: #{pr.successful_checks}/#{pr.total_checks} (#{pr.failed_checks} failed)"
    puts "Backend Approval: #{pr.backend_approval_status}"
  end
end

# Update first 10 PRs with full data
PullRequest.limit(10).each_with_index do |pr, index|
  puts "Updating PR ##{pr.number} (#{index + 1}/10)..."
  begin
    # Fetch CI checks
    scraper = EnhancedGithubScraperService.new
    check_data = scraper.scrape_pr_checks_detailed(pr.url)

    # Update PR with check data
    pr.update!(
      ci_status: check_data[:overall_status] || 'pending',
      total_checks: check_data[:total_checks] || 0,
      successful_checks: check_data[:successful_checks] || 0,
      failed_checks: check_data[:failed_checks] || 0
    )

    # Fetch reviews
    github_token = ENV['GITHUB_TOKEN']
    owner = ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs'
    repo = ENV['GITHUB_REPO'] || 'vets-api'
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

    puts "  ✓ Updated successfully"
  rescue => e
    puts "  ✗ Error: #{e.message}"
  end
end
puts 'Done! Refresh the frontend to see the updated data.'

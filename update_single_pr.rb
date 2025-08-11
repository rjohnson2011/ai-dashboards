pr_number = 23158

github_service = GithubService.new
scraper_service = EnhancedGithubScraperService.new

# Fetch PR from GitHub
pr = github_service.all_pull_requests(state: 'open').find { |p| p.number == pr_number }

if pr
  puts "Found PR ##{pr.number}: #{pr.title}"

  # Find or create PR record
  pr_record = PullRequest.find_or_initialize_by(github_id: pr.id)

  # Update basic info
  pr_record.assign_attributes(
    number: pr.number,
    title: pr.title,
    author: pr.user.login,
    state: pr.state,
    draft: pr.draft,
    url: pr.html_url,
    pr_created_at: pr.created_at,
    pr_updated_at: pr.updated_at
  )

  # Scrape CI checks
  puts "Scraping checks..."
  checks_data = scraper_service.scrape_pr_checks_detailed(pr.html_url)
  puts "Found #{checks_data[:total_checks]} checks"

  # Update PR with CI status
  pr_record.assign_attributes(
    ci_status: checks_data[:overall_status],
    total_checks: checks_data[:total_checks],
    successful_checks: checks_data[:successful_checks],
    failed_checks: checks_data[:failed_checks]
  )

  pr_record.save!

  # Clear existing check runs and create new ones
  pr_record.check_runs.destroy_all

  checks_data[:checks].each do |check|
    pr_record.check_runs.create!(
      name: check[:name],
      status: check[:status],
      url: check[:url],
      description: check[:description],
      required: check[:required],
      suite_name: check[:suite_name]
    )
  end

  puts "Updated PR ##{pr.number}:"
  puts "- Total checks: #{pr_record.total_checks}"
  puts "- Successful: #{pr_record.successful_checks}"
  puts "- Failed: #{pr_record.failed_checks}"
  puts "- CI Status: #{pr_record.ci_status}"
  puts "\nCheck statuses:"
  pr_record.check_runs.each do |check|
    puts "- #{check.name}: #{check.status}"
  end
else
  puts "PR ##{pr_number} not found"
end

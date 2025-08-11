pr = PullRequest.find_by(number: 23103)
puts "Updating PR #23103..."
scraper = EnhancedGithubScraperService.new
check_data = scraper.scrape_pr_checks_detailed(pr.url)
pr.update!(
  ci_status: check_data[:overall_status] || 'pending',
  total_checks: check_data[:total_checks] || 0,
  successful_checks: check_data[:successful_checks] || 0,
  failed_checks: check_data[:failed_checks] || 0
)
puts "Done! Stats:"
puts "  Total: #{pr.total_checks}"
puts "  Success: #{pr.successful_checks}"
puts "  Failed: #{pr.failed_checks}"

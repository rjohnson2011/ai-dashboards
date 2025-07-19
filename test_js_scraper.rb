pr = PullRequest.find_by(number: 23132)
puts "Testing JavaScript scraper on PR ##{pr.number}..."

scraper = JavascriptGithubScraperService.new
result = scraper.scrape_pr_checks_with_js(pr.url)

puts "\nResults:"
puts "  Total checks: #{result[:total_checks]}"
puts "  Successful: #{result[:successful_checks]}"
puts "  Failed: #{result[:failed_checks]}"
puts "  Status: #{result[:overall_status]}"

# Update the PR with correct data
if result[:total_checks] > 0
  pr.update!(
    total_checks: result[:total_checks],
    successful_checks: result[:successful_checks],
    failed_checks: result[:failed_checks],
    ci_status: result[:overall_status]
  )
  puts "\nUpdated PR ##{pr.number} in database"
end
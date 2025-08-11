pr = PullRequest.find_by(number: 23012)
puts "Debugging PR ##{pr.number} check counts..."

scraper = EnhancedGithubScraperService.new
check_data = scraper.scrape_pr_checks_detailed(pr.url)

puts "\nScraper results:"
puts "  Total checks: #{check_data[:total_checks]}"
puts "  Successful: #{check_data[:successful_checks]}"
puts "  Failed: #{check_data[:failed_checks]}"
puts "  Overall status: #{check_data[:overall_status]}"

if check_data[:summary_counts]
  puts "\nSummary counts found:"
  puts "  #{check_data[:summary_counts].inspect}"
end

if check_data[:checks]
  puts "\nIndividual checks found: #{check_data[:checks].length}"
  failed_checks = check_data[:checks].select { |c| c[:status] == 'failure' }
  puts "Failed checks (#{failed_checks.length}):"
  failed_checks.each { |c| puts "  - #{c[:name]}" }
end

# Test the scraper on multiple PRs to verify it captures different status patterns

pr_numbers = [23158, 23164, 23163, 23162, 23161]

github_service = GithubService.new
scraper_service = EnhancedGithubScraperService.new

pr_numbers.each do |pr_number|
  puts "\n" + "="*60
  puts "Testing PR ##{pr_number}"
  puts "="*60
  
  # Get PR from GitHub
  pr = github_service.all_pull_requests(state: 'open').find { |p| p.number == pr_number }
  
  if pr
    puts "Title: #{pr.title}"
    puts "URL: #{pr.html_url}"
    
    # Scrape checks
    checks_data = scraper_service.scrape_pr_checks_detailed(pr.html_url)
    
    puts "\nResults:"
    puts "- Overall status: #{checks_data[:overall_status]}"
    puts "- Total checks: #{checks_data[:total_checks]}"
    puts "- Successful: #{checks_data[:successful_checks]}"
    puts "- Failed: #{checks_data[:failed_checks]}"
    
    # Calculate pending/other
    pending_other = checks_data[:total_checks] - checks_data[:successful_checks] - checks_data[:failed_checks]
    puts "- Pending/Other: #{pending_other}" if pending_other > 0
    
    # Show check details if less than 10
    if checks_data[:checks].count <= 10
      puts "\nIndividual checks:"
      checks_data[:checks].each do |check|
        puts "  - #{check[:name]}: #{check[:status]}"
      end
    else
      puts "\nFound #{checks_data[:checks].count} individual checks (too many to display)"
    end
  else
    puts "PR ##{pr_number} not found"
  end
end

puts "\n" + "="*60
puts "Summary complete"
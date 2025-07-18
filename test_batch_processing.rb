#!/usr/bin/env ruby
require_relative 'config/environment'

puts "Testing batch processing of PRs..."
puts "Current PR count in database: #{PullRequest.count}"
puts "\n"

github_service = GithubService.new
scraper_service = EnhancedGithubScraperService.new

begin
  # Fetch just 3 PRs to test
  puts "Fetching 3 open PRs from GitHub API..."
  pull_requests = github_service.pull_requests(state: 'open', per_page: 3)
  
  puts "Found #{pull_requests.count} PRs to process"
  puts "\n"
  
  pull_requests.each_with_index do |pr, index|
    puts "Processing PR ##{pr.number}: #{pr.title} (#{index + 1}/#{pull_requests.count})"
    
    begin
      # Use a transaction with a lock
      PullRequest.transaction do
        pr_record = PullRequest.where(github_id: pr.id).lock.first
        pr_record ||= PullRequest.new(github_id: pr.id)
        
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
        
        puts "  - Basic info updated"
        
        # Scrape CI checks (with timeout)
        Timeout::timeout(10) do
          checks_data = scraper_service.scrape_pr_checks_detailed(pr.html_url)
          
          pr_record.assign_attributes(
            ci_status: checks_data[:overall_status],
            total_checks: checks_data[:total_checks],
            successful_checks: checks_data[:successful_checks],
            failed_checks: checks_data[:failed_checks]
          )
          
          puts "  - CI status: #{checks_data[:overall_status]} (#{checks_data[:total_checks]} checks)"
        end
        
        pr_record.save!
        puts "  - Saved successfully!"
      end
    rescue Timeout::Error => e
      puts "  - ERROR: Timeout while scraping"
    rescue => e
      puts "  - ERROR: #{e.message}"
    end
    
    puts "\n"
  end
  
  puts "Processing complete!"
  puts "Total PRs in database now: #{PullRequest.count}"
  
rescue => e
  puts "ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
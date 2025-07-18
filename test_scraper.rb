#!/usr/bin/env ruby
require_relative 'config/environment'

# Test the scraper with a specific PR
pr_url = "https://github.com/department-of-veterans-affairs/vets-api/pull/23172"

puts "Testing scraper on PR: #{pr_url}"
puts "\n"

scraper = EnhancedGithubScraperService.new

begin
  start_time = Time.now
  puts "Starting scrape at #{start_time}..."
  
  result = scraper.scrape_pr_checks_detailed(pr_url)
  
  end_time = Time.now
  puts "Scrape completed in #{(end_time - start_time).round(2)} seconds"
  puts "\n"
  
  puts "Results:"
  puts "Overall status: #{result[:overall_status]}"
  puts "Total checks: #{result[:total_checks]}"
  puts "Successful checks: #{result[:successful_checks]}"
  puts "Failed checks: #{result[:failed_checks]}"
  puts "\n"
  
  if result[:checks].any?
    puts "Individual checks found:"
    result[:checks].each do |check|
      puts "  - #{check[:name]} (#{check[:status]})"
    end
  else
    puts "No individual checks found"
  end
  
rescue => e
  puts "ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.first(10).join("\n")
end
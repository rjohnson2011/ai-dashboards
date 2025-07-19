#!/usr/bin/env ruby
require_relative 'config/environment'

puts "Testing scraping time for PR updates..."
puts "="*60

# Test 1: Basic PR fetch time
start_time = Time.now
github_service = GithubService.new
prs = github_service.all_pull_requests(state: 'open')
api_time = Time.now - start_time
puts "API call for #{prs.count} PRs took: #{api_time.round(2)} seconds"

# Test 2: Scraping check counts for a few PRs
scraper = EnhancedGithubScraperService.new
pr_samples = prs.sample(5)
scrape_times = []

pr_samples.each do |pr|
  start = Time.now
  result = scraper.scrape_pr_checks_detailed(pr.html_url)
  elapsed = Time.now - start
  scrape_times << elapsed
  puts "Scraping PR ##{pr.number}: #{elapsed.round(2)}s (#{result[:total_checks]} checks)"
end

avg_scrape_time = scrape_times.sum / scrape_times.length
puts "\nAverage scrape time per PR: #{avg_scrape_time.round(2)} seconds"

# Estimate total time for all PRs
estimated_total = api_time + (prs.count * avg_scrape_time)
puts "\nEstimated time to update all #{prs.count} PRs:"
puts "- API fetch: #{api_time.round(2)}s"
puts "- Scraping: #{(prs.count * avg_scrape_time).round(2)}s"
puts "- Total: #{estimated_total.round(2)}s (#{(estimated_total/60).round(2)} minutes)"

# GitHub Actions calculation
runs_per_day = 24 * 4  # Every 15 minutes
runs_per_month = runs_per_day * 30
minutes_per_run = (estimated_total / 60).ceil + 1  # Add 1 minute for overhead
total_minutes_per_month = minutes_per_run * runs_per_month

puts "\nGitHub Actions estimate:"
puts "- Runs per day: #{runs_per_day}"
puts "- Minutes per run: #{minutes_per_run}"
puts "- Total minutes per month: #{total_minutes_per_month}"
puts "- Free tier (2000 minutes): #{total_minutes_per_month > 2000 ? 'EXCEEDED' : 'OK'}"
puts "- Cost if exceeded: $#{((total_minutes_per_month - 2000) * 0.008).round(2)}"
#!/usr/bin/env ruby
require_relative 'config/environment'

puts "Testing GitHub API connection..."
puts "GitHub Token: #{ENV['GITHUB_TOKEN'].present? ? 'Present' : 'Missing'}"
puts "GitHub Owner: #{ENV['GITHUB_OWNER']}"
puts "GitHub Repo: #{ENV['GITHUB_REPO']}"
puts "\n"

begin
  service = GithubService.new
  
  # Test rate limit (simple API call)
  puts "Testing API access with rate limit check..."
  rate_limit = service.rate_limit
  puts "Rate limit remaining: #{rate_limit.remaining} / #{rate_limit.limit}"
  puts "Rate limit resets at: #{Time.at(rate_limit.resets_at)}"
  puts "\n"
  
  # Try to fetch just one PR
  puts "Fetching first open PR..."
  prs = service.pull_requests(state: 'open', per_page: 1)
  
  if prs.empty?
    puts "No open PRs found!"
  else
    pr = prs.first
    puts "Found PR ##{pr.number}: #{pr.title}"
    puts "Author: #{pr.user.login}"
    puts "Created: #{pr.created_at}"
  end
  
rescue Octokit::Unauthorized => e
  puts "ERROR: Unauthorized - Check your GitHub token"
  puts "Error: #{e.message}"
rescue Octokit::NotFound => e
  puts "ERROR: Repository not found - Check GITHUB_OWNER and GITHUB_REPO"
  puts "Error: #{e.message}"
rescue => e
  puts "ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
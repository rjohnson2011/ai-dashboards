#!/usr/bin/env ruby
# Debug script to check GitHub token configuration

puts "=== GitHub Token Debug ==="
puts "RAILS_ENV: #{ENV['RAILS_ENV']}"
puts "GITHUB_TOKEN present: #{ENV['GITHUB_TOKEN'].present?}"
puts "GITHUB_TOKEN length: #{ENV['GITHUB_TOKEN']&.length || 0}"
puts "GITHUB_TOKEN format: #{ENV['GITHUB_TOKEN']&.match?(/^(ghp_|github_pat_)/) ? 'Valid format' : 'Invalid format'}" if ENV['GITHUB_TOKEN']
puts "GITHUB_OWNER: #{ENV['GITHUB_OWNER']}"
puts "GITHUB_REPO: #{ENV['GITHUB_REPO']}"

if ENV['GITHUB_TOKEN'].present?
  require 'octokit'
  
  begin
    client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
    user = client.user
    puts "\n✅ Token is valid!"
    puts "Authenticated as: #{user.login}"
    
    rate_limit = client.rate_limit
    puts "\nRate limit info:"
    puts "  Limit: #{rate_limit.limit}"
    puts "  Remaining: #{rate_limit.remaining}"
    puts "  Resets at: #{rate_limit.resets_at}"
  rescue Octokit::Unauthorized => e
    puts "\n❌ Token is invalid: #{e.message}"
    puts "Please check:"
    puts "1. Token hasn't expired"
    puts "2. Token has 'repo' scope"
    puts "3. No extra spaces or quotes around token"
  rescue => e
    puts "\n❌ Error: #{e.message}"
  end
else
  puts "\n❌ GITHUB_TOKEN is not set!"
  puts "Add it to your cron job environment variables"
end
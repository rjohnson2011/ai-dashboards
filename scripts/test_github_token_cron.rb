#!/usr/bin/env ruby
# Simple test script for debugging GitHub token in cron job

puts "=== GitHub Token Test for Cron Job ==="
puts "Time: #{Time.now}"
puts "Ruby version: #{RUBY_VERSION}"
puts "Rails env: #{ENV['RAILS_ENV']}"

# Check token
token = ENV['GITHUB_TOKEN']
if token.nil?
  puts "ERROR: GITHUB_TOKEN is nil"
  exit 1
elsif token.empty?
  puts "ERROR: GITHUB_TOKEN is empty string"
  exit 1
else
  puts "Token present: Yes"
  puts "Token length: #{token.length}"
  puts "Token preview: #{token[0..7]}...#{token[-4..-1]}"
  puts "Starts with ghp_? #{token.start_with?('ghp_')}"
  puts "Starts with github_pat_? #{token.start_with?('github_pat_')}"
  puts "Contains quotes? #{token.include?('"') || token.include?("'")}"
  puts "Has whitespace? #{token != token.strip}"
end

# Test with curl
puts "\nTesting with curl..."
require 'open3'
cmd = "curl -s -H 'Authorization: token #{token}' https://api.github.com/rate_limit"
stdout, stderr, status = Open3.capture3(cmd)

puts "Curl exit code: #{status.exitstatus}"
if status.success?
  require 'json'
  begin
    data = JSON.parse(stdout)
    if data['rate']
      puts "SUCCESS! Rate limit: #{data['rate']['remaining']}/#{data['rate']['limit']}"
    else
      puts "Unexpected response: #{stdout[0..200]}"
    end
  rescue => e
    puts "Failed to parse JSON: #{e.message}"
    puts "Raw response: #{stdout[0..200]}"
  end
else
  puts "Curl failed: #{stderr}"
end

# Test with Octokit
puts "\nTesting with Octokit..."
begin
  require 'octokit'
  client = Octokit::Client.new(access_token: token)
  user = client.user
  puts "SUCCESS! Authenticated as: #{user.login}"
  
  rate = client.rate_limit
  puts "Rate limit: #{rate.remaining}/#{rate.limit}"
rescue => e
  puts "Octokit failed: #{e.class} - #{e.message}"
end

puts "\nTest complete."
#!/usr/bin/env ruby
require_relative 'config/environment'

puts "Current Rails environment: #{Rails.env}"
puts "Active Job queue adapter: #{Rails.application.config.active_job.queue_adapter}"
puts "Cache store: #{Rails.cache.class}"
puts "\n"

# Check current refresh status
current_status = Rails.cache.read('refresh_status')
puts "Current refresh status: #{current_status.inspect}"
puts "\n"

# Check if we have the necessary environment variables
puts "GitHub Token present: #{ENV['GITHUB_TOKEN'].present?}"
puts "GitHub Owner: #{ENV['GITHUB_OWNER']}"
puts "GitHub Repo: #{ENV['GITHUB_REPO']}"
puts "\n"

# Try to execute the job synchronously
puts "Executing FetchPullRequestDataJob synchronously..."
begin
  job = FetchPullRequestDataJob.new
  job.perform
  puts "Job executed successfully!"
rescue => e
  puts "Error executing job: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Check the status again
new_status = Rails.cache.read('refresh_status')
puts "\nRefresh status after job: #{new_status.inspect}"

# Check if any pull requests were created/updated
puts "\nTotal pull requests in database: #{PullRequest.count}"
puts "Recent pull requests:"
PullRequest.order(updated_at: :desc).limit(5).each do |pr|
  puts "  ##{pr.number} - #{pr.title} (Updated: #{pr.updated_at})"
end
#!/usr/bin/env ruby
require_relative 'config/environment'

puts "=== FetchPullRequestDataJob Diagnosis ==="
puts "Rails environment: #{Rails.env}"
puts "Active Job adapter: #{ActiveJob::Base.queue_adapter.class}"
puts "\n"

# Check environment
puts "Environment Configuration:"
puts "  GitHub Token: #{ENV['GITHUB_TOKEN'].present? ? 'Present' : 'MISSING!'}"
puts "  GitHub Owner: #{ENV['GITHUB_OWNER']}"
puts "  GitHub Repo: #{ENV['GITHUB_REPO']}"
puts "\n"

# Check current status
refresh_status = Rails.cache.read('refresh_status')
lock_status = Rails.cache.read('fetch_pull_request_data_job_lock')
last_refresh = Rails.cache.read('last_refresh_time')

puts "Current Status:"
puts "  Refresh status: #{refresh_status.inspect}"
puts "  Job lock: #{lock_status.present? ? 'LOCKED' : 'Available'}"
puts "  Last refresh: #{last_refresh || 'Never'}"
puts "\n"

# Test GitHub API
puts "Testing GitHub API..."
begin
  service = GithubService.new
  rate_limit = service.rate_limit
  puts "  Rate limit: #{rate_limit.remaining}/#{rate_limit.limit}"

  pr_count = service.all_pull_requests(state: 'open').count
  puts "  Open PRs in repo: #{pr_count}"
rescue => e
  puts "  ERROR: #{e.message}"
end
puts "\n"

# Database status
puts "Database Status:"
puts "  Total PRs stored: #{PullRequest.count}"
puts "  PRs updated today: #{PullRequest.where('updated_at > ?', 1.day.ago).count}"
puts "\n"

# Issues and recommendations
puts "=== DIAGNOSIS ==="
puts "\nThe issue appears to be that the FetchPullRequestDataJob is taking too long to complete."
puts "\nREASONS:"
puts "1. The job processes ALL open PRs sequentially in a single job"
puts "2. For each PR, it makes an HTTP request to scrape the checks page"
puts "3. With #{pr_count rescue 'many'} open PRs, this can take 30+ minutes"
puts "4. The async job adapter in development runs jobs in background threads"
puts "5. The 'updating: true' status persists because the job is still running"
puts "\nRECOMMENDATIONS:"
puts "1. Use the optimized job (FetchPullRequestDataOptimizedJob) that processes in batches"
puts "2. Configure a proper job queue (Sidekiq or SolidQueue) for development"
puts "3. Add timeouts to the scraping operations"
puts "4. Consider caching scraper results"
puts "5. Process only recently updated PRs more frequently"
puts "\nQUICK FIX:"
puts "To clear the stuck status and test the optimized job:"
puts "  rails runner \"Rails.cache.clear\""
puts "  rails runner \"FetchPullRequestDataOptimizedJob.perform_later\""

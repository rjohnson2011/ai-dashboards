#!/usr/bin/env ruby
require_relative 'config/environment'

puts "Testing job queue configuration..."
puts "Rails environment: #{Rails.env}"
puts "Active Job adapter: #{ActiveJob::Base.queue_adapter.class}"
puts "\n"

# Set the refresh status to see if it persists
Rails.cache.write('refresh_status', { updating: true, progress: { current: 0, total: 0 } })
puts "Set refresh status to 'updating: true'"

# Queue the job
puts "Queuing FetchPullRequestDataJob..."
job = FetchPullRequestDataJob.perform_later
puts "Job queued with ID: #{job.job_id}"
puts "Job class: #{job.class}"
puts "\n"

# In development with async adapter, jobs run in background threads
# Let's wait a bit and check the status
puts "Waiting 5 seconds for job to start..."
sleep 5

status = Rails.cache.read('refresh_status')
puts "Current refresh status: #{status.inspect}"
puts "\n"

# Check if there's a lock
lock_key = 'fetch_pull_request_data_job_lock'
lock_status = Rails.cache.read(lock_key)
puts "Job lock status: #{lock_status.inspect}"

# Let's also check what queue adapter we should use
puts "\n"
puts "For development, you might want to use inline adapter for debugging:"
puts "  config.active_job.queue_adapter = :inline"
puts "\nOr use Sidekiq/SolidQueue for better job handling."
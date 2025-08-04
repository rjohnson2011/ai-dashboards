#!/usr/bin/env ruby
require_relative 'config/environment'

puts "\n=== CHECKING CRON JOB LOGS ===\n"

# Check recent cron job logs
total_logs = CronJobLog.count
puts "Total cron job logs in database: #{total_logs}"

if total_logs > 0
  puts "\nLast 20 cron job executions:"
  puts "-" * 100
  
  CronJobLog.order(created_at: :desc).limit(20).each do |log|
    puts "Started: #{log.started_at&.strftime('%Y-%m-%d %H:%M:%S')} | Status: #{log.status}"
    puts "  Completed: #{log.completed_at&.strftime('%Y-%m-%d %H:%M:%S') || 'N/A'}"
    puts "  PRs processed: #{log.prs_processed || 0} | PRs updated: #{log.prs_updated || 0}"
    if log.error_message.present?
      puts "  ERROR: #{log.error_class} - #{log.error_message}"
    end
    puts "-" * 100
  end
end

puts "\n=== CHECKING DAILY METRICS CAPTURE JOB ===\n"

# Look for the daily metrics capture script
capture_script = File.join(Rails.root, 'scripts', 'capture_daily_metrics.rb')
if File.exist?(capture_script)
  puts "Daily metrics capture script exists at: #{capture_script}"
else
  puts "WARNING: Daily metrics capture script not found!"
end

# Check cron configuration
puts "\n=== CHECKING CRON/SCHEDULED JOB CONFIGURATION ===\n"

# Check for render.yaml cron configuration
render_config = File.join(Rails.root, 'render.yaml')
if File.exist?(render_config)
  puts "Render configuration found. Checking for cron jobs..."
  content = File.read(render_config)
  if content.include?('daily-metrics-capture')
    puts "✓ Daily metrics capture cron job is configured in render.yaml"
    puts "  Schedule: " + content[/schedule:\s*"([^"]+)"/, 1].to_s
  else
    puts "✗ Daily metrics capture cron job NOT found in render.yaml"
  end
end

# Check recurring jobs configuration
recurring_file = File.join(Rails.root, 'config', 'recurring.yml')
if File.exist?(recurring_file)
  puts "\nRecurring jobs configuration found at: #{recurring_file}"
  puts File.read(recurring_file)
end

# Check for background job configuration
puts "\n=== CHECKING BACKGROUND JOBS ===\n"

# Look for capture daily metrics job
job_file = File.join(Rails.root, 'app', 'jobs', 'capture_daily_metrics_job.rb')
if File.exist?(job_file)
  puts "CaptureDailyMetricsJob exists"
  
  # Try to see if we can check Solid Queue scheduled jobs
  begin
    # This might not work if Solid Queue isn't configured, but let's try
    if defined?(SolidQueue)
      scheduled_count = SolidQueue::ScheduledJob.count rescue 0
      puts "Scheduled jobs in queue: #{scheduled_count}"
    end
  rescue => e
    puts "Could not check Solid Queue: #{e.message}"
  end
else
  puts "CaptureDailyMetricsJob NOT found"
end

puts "\n=== MANUALLY CAPTURING TODAY'S SNAPSHOT ===\n"
puts "Attempting to capture a snapshot for today..."

begin
  snapshot = DailySnapshot.capture_snapshot!
  puts "✓ Successfully captured snapshot for #{snapshot.snapshot_date}"
  puts "  Total PRs: #{snapshot.total_prs}"
  puts "  Approved PRs: #{snapshot.approved_prs}"
rescue => e
  puts "✗ Failed to capture snapshot: #{e.message}"
end
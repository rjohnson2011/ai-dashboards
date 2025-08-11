#!/usr/bin/env ruby
# Local sync daemon - runs from your machine to avoid Render IP issues
# This uses YOUR IP address which won't be rate limited

require 'net/http'
require 'json'
require 'uri'
require 'logger'

# Configuration
API_URL = ENV['API_URL'] || 'https://ai-dashboards.onrender.com'
ADMIN_TOKEN = ENV['ADMIN_TOKEN']
SYNC_INTERVAL = (ENV['SYNC_INTERVAL'] || '1800').to_i # 30 minutes default

# Set up logging
logger = Logger.new(STDOUT)
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

# Validate configuration
if ADMIN_TOKEN.nil? || ADMIN_TOKEN.empty?
  logger.error "ADMIN_TOKEN environment variable not set!"
  puts "Usage: ADMIN_TOKEN=your_token ruby local_sync_daemon.rb"
  exit 1
end

logger.info "Starting Local Sync Daemon"
logger.info "API URL: #{API_URL}"
logger.info "Sync interval: #{SYNC_INTERVAL} seconds"

# Check our IP
begin
  ip_response = Net::HTTP.get(URI('https://api.ipify.org?format=json'))
  current_ip = JSON.parse(ip_response)['ip']
  logger.info "Running from IP: #{current_ip} (your local IP)"
rescue => e
  logger.warn "Could not determine IP: #{e.message}"
end

def sync_pr_data(logger)
  uri = URI("#{API_URL}/api/v1/admin/update_full_data")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 300 # 5 minute timeout for full sync

  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'
  request.body = { token: ADMIN_TOKEN }.to_json

  logger.info "Starting PR data sync..."
  start_time = Time.now

  response = http.request(request)
  duration = (Time.now - start_time).round(2)

  if response.code == '200'
    data = JSON.parse(response.body) rescue {}
    logger.info "Sync completed in #{duration}s"
    logger.info "Updated: #{data['updated_count']} PRs"
    logger.info "Errors: #{data['errors']&.length || 0}"
    true
  else
    logger.error "Sync failed: #{response.code} - #{response.body}"
    false
  end
rescue => e
  logger.error "Sync error: #{e.message}"
  false
end

# Signal handlers for graceful shutdown
trap('INT') do
  logger.info "Received interrupt signal, shutting down..."
  exit 0
end

trap('TERM') do
  logger.info "Received termination signal, shutting down..."
  exit 0
end

# Main loop
logger.info "Daemon started. Press Ctrl+C to stop."
consecutive_failures = 0

loop do
  begin
    success = sync_pr_data(logger)

    if success
      consecutive_failures = 0
    else
      consecutive_failures += 1
      if consecutive_failures >= 3
        logger.error "3 consecutive failures, waiting longer before retry"
        sleep(300) # Wait 5 minutes on repeated failures
      end
    end

    next_sync = Time.now + SYNC_INTERVAL
    logger.info "Next sync at: #{next_sync.strftime('%H:%M:%S')}"
    logger.info "-" * 50

    sleep(SYNC_INTERVAL)

  rescue => e
    logger.error "Unexpected error: #{e.message}"
    logger.error e.backtrace.first(5).join("\n")
    sleep(60) # Wait 1 minute on unexpected errors
  end
end

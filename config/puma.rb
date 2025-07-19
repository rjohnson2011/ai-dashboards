# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.

# Puma configuration
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# Workers for production
workers ENV.fetch("WEB_CONCURRENCY") { 2 } if ENV["RAILS_ENV"] == "production"

# Preload app for performance
preload_app! if ENV["RAILS_ENV"] == "production"

# Simple background job runner for production
on_worker_boot do
  if ENV['RAILS_ENV'] == 'production' && ENV['ADMIN_TOKEN'].present?
    Thread.new do
      sleep 30 # Wait for Rails to fully initialize
      Rails.logger.info "[BackgroundJobs] Starting simple update scheduler at #{Time.current}"
      Rails.logger.info "[BackgroundJobs] Will run every 15 minutes"
      
      # Log to a file as well for persistence
      File.open('/tmp/background_jobs.log', 'a') do |f|
        f.puts "[#{Time.current}] Background job scheduler started"
      end
      
      loop do
        begin
          start_time = Time.current
          Rails.logger.info "[BackgroundJobs] === Starting scheduled update cycle at #{start_time} ==="
          
          # Log to file
          File.open('/tmp/background_jobs.log', 'a') do |f|
            f.puts "[#{start_time}] Starting update cycle"
          end
          
          # Update PR data
          uri = URI("https://ai-dashboards.onrender.com/api/v1/admin/update_data")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          
          request = Net::HTTP::Post.new(uri)
          request['Content-Type'] = 'application/json'
          request.body = { token: ENV['ADMIN_TOKEN'] }.to_json
          
          response = http.request(request)
          Rails.logger.info "[BackgroundJobs] Update data response: #{response.code} - #{response.body}"
          
          # Log to file
          File.open('/tmp/background_jobs.log', 'a') do |f|
            f.puts "[#{Time.current}] Update data response: #{response.code}"
          end
          
          # Clean up merged/closed PRs
          Rails.logger.info "[BackgroundJobs] Running cleanup of merged PRs..."
          cleanup_uri = URI("https://ai-dashboards.onrender.com/api/v1/admin/cleanup_merged_prs")
          cleanup_request = Net::HTTP::Post.new(cleanup_uri)
          cleanup_request['Content-Type'] = 'application/json'
          cleanup_request.body = { token: ENV['ADMIN_TOKEN'] }.to_json
          
          cleanup_response = http.request(cleanup_request)
          Rails.logger.info "[BackgroundJobs] Cleanup response: #{cleanup_response.code} - #{cleanup_response.body}"
          
          # Log to file
          File.open('/tmp/background_jobs.log', 'a') do |f|
            f.puts "[#{Time.current}] Cleanup response: #{cleanup_response.code}"
          end
          
          # Update checks via GitHub API
          Rails.logger.info "[BackgroundJobs] Updating PR checks via GitHub API..."
          checks_uri = URI("https://ai-dashboards.onrender.com/api/v1/admin/update_checks_via_api")
          checks_request = Net::HTTP::Post.new(checks_uri)
          checks_request['Content-Type'] = 'application/json'
          checks_request.body = { token: ENV['ADMIN_TOKEN'] }.to_json
          
          checks_response = http.request(checks_request)
          Rails.logger.info "[BackgroundJobs] Checks update response: #{checks_response.code} - #{checks_response.body}"
          
          # Log to file
          File.open('/tmp/background_jobs.log', 'a') do |f|
            f.puts "[#{Time.current}] Checks update response: #{checks_response.code}"
          end
          
          end_time = Time.current
          duration = (end_time - start_time).round(2)
          Rails.logger.info "[BackgroundJobs] === Update cycle completed in #{duration} seconds ==="
          Rails.logger.info "[BackgroundJobs] Next update will run at #{end_time + 900}"
          
          # Log completion to file
          File.open('/tmp/background_jobs.log', 'a') do |f|
            f.puts "[#{end_time}] Update cycle completed in #{duration}s. Next run at #{end_time + 900}"
            f.puts "----------------------------------------"
          end
          
          # Sleep for 15 minutes
          sleep(900)
        rescue => e
          Rails.logger.error "[BackgroundJobs] Error in update scheduler: #{e.message}"
          Rails.logger.error "[BackgroundJobs] Backtrace: #{e.backtrace.first(5).join("\n")}"
          
          # Log error to file
          File.open('/tmp/background_jobs.log', 'a') do |f|
            f.puts "[#{Time.current}] ERROR: #{e.message}"
            f.puts "----------------------------------------"
          end
          
          sleep(60) # Sleep for a minute on error
        end
      end
    end
  end
end
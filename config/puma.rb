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
      Rails.logger.info "[BackgroundJobs] Starting simple update scheduler"
      
      loop do
        begin
          Rails.logger.info "[BackgroundJobs] Running scheduled update at #{Time.current}"
          
          # Update PR data
          uri = URI("https://ai-dashboards.onrender.com/api/v1/admin/update_data")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          
          request = Net::HTTP::Post.new(uri)
          request['Content-Type'] = 'application/json'
          request.body = { token: ENV['ADMIN_TOKEN'] }.to_json
          
          response = http.request(request)
          Rails.logger.info "[BackgroundJobs] Update response: #{response.code} - #{response.body}"
          
          # Clean up merged/closed PRs
          Rails.logger.info "[BackgroundJobs] Running cleanup of merged PRs..."
          cleanup_uri = URI("https://ai-dashboards.onrender.com/api/v1/admin/cleanup_merged_prs")
          cleanup_request = Net::HTTP::Post.new(cleanup_uri)
          cleanup_request['Content-Type'] = 'application/json'
          cleanup_request.body = { token: ENV['ADMIN_TOKEN'] }.to_json
          
          cleanup_response = http.request(cleanup_request)
          Rails.logger.info "[BackgroundJobs] Cleanup response: #{cleanup_response.code} - #{cleanup_response.body}"
          
          # Sleep for 15 minutes
          sleep(900)
        rescue => e
          Rails.logger.error "[BackgroundJobs] Error in update scheduler: #{e.message}"
          sleep(60) # Sleep for a minute on error
        end
      end
    end
  end
end
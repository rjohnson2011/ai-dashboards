# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.

# Puma configuration for webhook-based updates
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

# With webhooks, we only need a cleanup job for old webhook events
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)

  if ENV["RAILS_ENV"] == "production"
    Thread.new do
      Rails.logger.info "[WebhookCleanup] Starting webhook event cleanup thread..."
      sleep 3600 # Wait 1 hour before first run

      loop do
        begin
          # Clean up webhook events older than 7 days
          old_events = WebhookEvent.cleanup_old_events
          Rails.logger.info "[WebhookCleanup] Cleaned up #{old_events} old webhook events"

          # Sleep for 24 hours
          sleep(86400)
        rescue => e
          Rails.logger.error "[WebhookCleanup] Error: #{e.message}"
          sleep(3600) # Sleep for 1 hour on error
        end
      end
    end
  end
end

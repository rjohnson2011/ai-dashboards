# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.

# Puma configuration optimized for Render free tier (512MB RAM)
# Use fewer threads to reduce memory footprint
threads_count = ENV.fetch("RAILS_MAX_THREADS", 2)
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

# Workers for production - reduced to 1 for free tier memory constraints
# Each worker uses ~150-200MB, so 1 worker keeps us under 512MB limit
workers ENV.fetch("WEB_CONCURRENCY") { 1 } if ENV["RAILS_ENV"] == "production"

# Preload app for performance and memory sharing via copy-on-write
preload_app! if ENV["RAILS_ENV"] == "production"

# Reduce memory by running GC more aggressively before forking
before_fork do
  GC.compact if GC.respond_to?(:compact)
end

# Cron jobs handle all updates now - no background jobs needed
# This prevents rate limit issues from the web service IP
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)

  # Log that we're using cron jobs instead
  if ENV["RAILS_ENV"] == "production"
    Rails.logger.info "[Puma] Started - Updates handled by Render cron jobs"
  end
end

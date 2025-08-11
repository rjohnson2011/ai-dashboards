# Configure Active Job queue adapter for development
# This makes jobs run synchronously in development for easier debugging
if Rails.env.development?
  Rails.application.config.active_job.queue_adapter = :inline
end

# Skip this initializer during asset precompilation and db:migrate
return if ENV["RAILS_ENV"] == "production" && (ENV["DATABASE_URL"].blank? || ARGV.any? { |arg| arg.include?("db:migrate") || arg.include?("assets:precompile") })

Rails.application.config.after_initialize do
  # Only run if we're in a server context (not rake tasks)
  if defined?(Rails::Server) && (Rails.env.production? || Rails.env.development?)
    Rails.logger.info "Setting up recurring job for pull request data fetch"

    # Only run if database is connected
    begin
      if ActiveRecord::Base.connected? && PullRequest.table_exists?
        # Run the job immediately on startup if no PR data exists
        if PullRequest.count == 0
          ActiveJob::Base.queue_adapter.enqueue_at(
            FetchPullRequestDataJob.new,
            10.seconds.from_now
          )
          Rails.logger.info "Scheduled initial pull request data fetch"
        end
      end
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      Rails.logger.warn "Database not available, skipping initial job scheduling"
    end
  end
end

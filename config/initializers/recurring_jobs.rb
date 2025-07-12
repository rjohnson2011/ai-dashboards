Rails.application.config.after_initialize do
  # Schedule the pull request data fetch job to run every 15 minutes
  
  if Rails.env.production? || Rails.env.development?
    Rails.logger.info "Setting up recurring job for pull request data fetch"
    
    # For now, we'll trigger the job manually and set up cron later
    # Run the job immediately on startup if no PR data exists
    ActiveJob::Base.queue_adapter.enqueue_at(
      FetchPullRequestDataJob.new, 
      10.seconds.from_now
    ) if PullRequest.count == 0
  end
end
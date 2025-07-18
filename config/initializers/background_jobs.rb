# Simple background job scheduler for Render free plan
# This runs within the web service process

Rails.application.config.after_initialize do
  if defined?(Rails::Server) && Rails.env.production?
    Thread.new do
      loop do
        begin
          # Run every 15 minutes
          Rails.logger.info "[BackgroundJobs] Starting scheduled jobs at #{Time.current}"
          
          # Fetch pull request data
          FetchPullRequestDataJob.perform_later
          Rails.logger.info "[BackgroundJobs] Scheduled FetchPullRequestDataJob"
          
          # Check if it's time for daily jobs (2 AM)
          current_hour = Time.current.hour
          if current_hour == 2
            # Run daily jobs
            CaptureDailySnapshotJob.perform_later
            FetchBackendReviewGroupJob.perform_later
            Rails.logger.info "[BackgroundJobs] Scheduled daily jobs"
            
            # Sleep for an hour to avoid running daily jobs multiple times
            sleep(3600)
          else
            # Sleep for 15 minutes
            sleep(900)
          end
        rescue => e
          Rails.logger.error "[BackgroundJobs] Error in background job scheduler: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          sleep(60) # Sleep for a minute on error
        end
      end
    end
  end
end
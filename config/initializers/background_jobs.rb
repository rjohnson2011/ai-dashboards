# Simple background job scheduler for Render free plan
# This runs within the web service process

Rails.application.config.after_initialize do
  if Rails.env.development? && ENV["RUN_BACKGROUND_JOBS"] == "true"
    Rails.logger.info "[BackgroundJobs] Initializing background job scheduler for development"
    Thread.new do
      sleep 30 # Wait for Rails to initialize

      loop do
        begin
          # Run every 15 minutes
          Rails.logger.info "[BackgroundJobs] Starting scheduled jobs at #{Time.current}"

          # Clean up merged/closed PRs
          Rails.logger.info "[BackgroundJobs] Checking for merged/closed PRs..."
          updated_count = 0

          github_token = ENV["GITHUB_TOKEN"]
          owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
          repo = ENV["GITHUB_REPO"] || "vets-api"
          client = Octokit::Client.new(access_token: github_token)

          PullRequest.where(state: "open").find_each do |pr|
            begin
              github_pr = client.pull_request("#{owner}/#{repo}", pr.number)

              if github_pr.state == "closed"
                pr.update!(state: github_pr.merged ? "merged" : "closed")
                updated_count += 1
                Rails.logger.info "[BackgroundJobs] Updated PR ##{pr.number} to #{pr.state}"
              end
            rescue Octokit::NotFound
              pr.destroy
              Rails.logger.info "[BackgroundJobs] Deleted PR ##{pr.number} (not found)"
            rescue => e
              Rails.logger.error "[BackgroundJobs] Error checking PR ##{pr.number}: #{e.message}"
            end
          end

          Rails.logger.info "[BackgroundJobs] Cleanup complete: #{updated_count} PRs updated"

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

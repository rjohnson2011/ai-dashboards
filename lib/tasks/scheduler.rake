namespace :scheduler do
  desc "Fetch pull request data (runs every 15 minutes)"
  task fetch_pull_requests: :environment do
    Rails.logger.info "Scheduler: Starting pull request data fetch"
    FetchPullRequestDataJob.perform_later
    Rails.logger.info "Scheduler: Pull request data fetch job queued"
  end
end

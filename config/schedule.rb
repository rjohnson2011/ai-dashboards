# Use this file to easily define all of your cron jobs.
# Learn more: http://github.com/javan/whenever

# Set the environment
set :output, "log/cron.log"

# Run the fetch pull request data job for all repositories
# More frequent during business hours (8 AM - 8 PM EST) to handle higher PR volume
every 15.minutes do
  runner <<-'RUBY'
    # Get current hour in EST
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]
    current_hour = est_zone.now.hour

    # Run every 15 minutes during business hours (8 AM - 8 PM EST)
    # Run every 30 minutes outside business hours (skip every other run)
    if (8..19).cover?(current_hour) || Time.current.min < 30
      RepositoryConfig.all.each do |repo|
        FetchAllPullRequestsJob.perform_later(
          repository_name: repo.name,
          repository_owner: repo.owner
        )
      end
    end
  RUBY
end

# Deep verification of all PRs (includes closed/merged PRs, review verification, HTML scraping)
# Runs once a day at 1 AM to minimize memory usage during peak hours
every 1.day, at: "1:00 am" do
  runner <<-'RUBY'
    RepositoryConfig.all.each do |repo|
      FetchAllPullRequestsJob.perform_later(
        repository_name: repo.name,
        repository_owner: repo.owner,
        deep_verification: true
      )
    end
  RUBY
end

# Capture daily metrics for all repositories at 2 AM every day (including weekends)
every 1.day, at: "2:00 am" do
  runner "CaptureAllDailyMetricsJob.perform_later"
end

# Fetch backend review group members at 2 AM every day
every 1.day, at: "2:00 am" do
  runner "FetchBackendReviewGroupJob.perform_later"
end

# Verify daily metrics were captured - runs at 9 AM to catch any 2 AM failures
every 1.day, at: "9:00 am" do
  runner "VerifyDailyMetricsJob.perform_later"
end

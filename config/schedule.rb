# Use this file to easily define all of your cron jobs.
# Learn more: http://github.com/javan/whenever

# Set the environment
set :output, "log/cron.log"

# Run the fetch pull request data job for all repositories every 30 minutes
# Reduced from 15 minutes to minimize memory usage and API costs
every 30.minutes do
  runner <<-'RUBY'
    RepositoryConfig.all.each do |repo|
      FetchAllPullRequestsJob.perform_later(
        repository_name: repo.name,
        repository_owner: repo.owner
      )
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

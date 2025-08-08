# Use this file to easily define all of your cron jobs.
# Learn more: http://github.com/javan/whenever

# Set the environment
set :output, "log/cron.log"

# Run the fetch pull request data job for vets-api every 15 minutes
every 15.minutes do
  runner "FetchAllPullRequestsJob.perform_later(repository_name: 'vets-api', repository_owner: 'department-of-veterans-affairs')"
end

# Capture daily metrics for vets-api at 2 AM every day (including weekends)
every 1.day, at: '2:00 am' do
  runner "CaptureDailyMetricsJob.perform_later(repository_name: 'vets-api', repository_owner: 'department-of-veterans-affairs')"
end

# Fetch backend review group members at 2 AM every day
every 1.day, at: '2:00 am' do
  runner "FetchBackendReviewGroupJob.perform_later"
end
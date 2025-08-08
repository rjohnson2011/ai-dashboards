# Use this file to easily define all of your cron jobs.
# Learn more: http://github.com/javan/whenever

# Set the environment
set :output, "log/cron.log"

# Run the fetch pull request data job for vets-api every 15 minutes
every 15.minutes do
  runner "FetchAllPullRequestsJob.perform_later(repository_name: 'vets-api', repository_owner: 'department-of-veterans-affairs')"
end

# Capture daily metrics for all repositories at 2 AM every day (including weekends)
every 1.day, at: '2:00 am' do
  runner "CaptureAllDailyMetricsJob.perform_later"
end

# Fetch backend review group members at 2 AM every day
every 1.day, at: '2:00 am' do
  runner "FetchBackendReviewGroupJob.perform_later"
end

# Verify daily metrics were captured - runs at 9 AM to catch any 2 AM failures
every 1.day, at: '9:00 am' do
  runner "VerifyDailyMetricsJob.perform_later"
end

# Fetch data for other repositories hourly (except vets-api which runs every 15 min)
every 1.hour do
  runner <<-'RUBY'
    RepositoryConfig.all.each do |repo|
      next if repo.name == 'vets-api' # Skip vets-api as it has its own schedule
      
      FetchAllPullRequestsJob.perform_later(
        repository_name: repo.name,
        repository_owner: repo.owner
      )
      
      # Also capture daily metrics if it's a new day
      last_snapshot = DailySnapshot.where(
        repository_name: repo.name,
        repository_owner: repo.owner,
        snapshot_date: Date.current
      ).first
      
      if last_snapshot.nil?
        CaptureDailyMetricsJob.perform_later(
          repository_name: repo.name,
          repository_owner: repo.owner
        )
      end
    end
  RUBY
end
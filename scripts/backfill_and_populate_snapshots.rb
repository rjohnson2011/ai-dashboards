#!/usr/bin/env ruby

puts "Starting backfill and population of snapshots..."

# First, backfill missing days for vets-api
missing_dates = [ '2025-08-05', '2025-08-07', '2025-08-08' ].map(&:to_date)

missing_dates.each do |date|
  puts "\nBackfilling vets-api for #{date}..."

  # Create a snapshot with default values for now
  snapshot = DailySnapshot.find_or_initialize_by(
    snapshot_date: date,
    repository_name: 'vets-api',
    repository_owner: 'department-of-veterans-affairs'
  )

  # Get current PR count as approximation
  base_scope = PullRequest.where(
    repository_name: 'vets-api',
    repository_owner: 'department-of-veterans-affairs'
  )

  snapshot.update!(
    total_prs: base_scope.open.count,
    approved_prs: base_scope.open.select { |pr| pr.approval_summary && pr.approval_summary[:approved_count] > 0 }.count,
    prs_with_changes_requested: base_scope.open.select { |pr| pr.approval_summary && pr.approval_summary[:status] == 'changes_requested' }.count,
    pending_review_prs: base_scope.open.where(draft: false).count,
    draft_prs: base_scope.open.where(draft: true).count,
    failing_ci_prs: base_scope.open.where(ci_status: 'failure').count,
    successful_ci_prs: base_scope.open.where(ci_status: 'success').count,
    prs_opened_today: 0, # Can't accurately backfill this
    prs_closed_today: 0, # Can't accurately backfill this
    prs_merged_today: 0  # Can't accurately backfill this
  )

  puts "Created snapshot for #{date}"
end

# Now run immediate population for all repositories
puts "\n\nPopulating data for all repositories..."

RepositoryConfig.all.each do |repo|
  puts "\nProcessing #{repo.full_name}..."

  # Fetch PRs
  FetchAllPullRequestsJob.perform_now(
    repository_name: repo.name,
    repository_owner: repo.owner
  )

  # Capture today's metrics
  CaptureDailyMetricsJob.perform_now(
    repository_name: repo.name,
    repository_owner: repo.owner
  )

  puts "Completed #{repo.full_name}"
end

puts "\n\nBackfill and population complete!"

# Show current snapshot counts
RepositoryConfig.all.each do |repo|
  count = DailySnapshot.where(
    repository_name: repo.name,
    repository_owner: repo.owner
  ).count

  puts "#{repo.full_name}: #{count} snapshots"
end

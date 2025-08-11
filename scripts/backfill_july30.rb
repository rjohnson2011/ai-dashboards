#!/usr/bin/env ruby
# Backfill data for July 30

yesterday = Date.yesterday
github_service = GithubService.new

# Fetch PRs for yesterday
day_before = yesterday - 1.day

opened_prs = github_service.search_pull_requests(
  query: "repo:#{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']} is:pr created:#{day_before.iso8601}..#{yesterday.iso8601}",
  per_page: 100
)

closed_prs = github_service.search_pull_requests(
  query: "repo:#{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']} is:pr is:closed closed:#{day_before.iso8601}..#{yesterday.iso8601}",
  per_page: 100
)

merged_prs = github_service.search_pull_requests(
  query: "repo:#{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']} is:pr is:merged merged:#{day_before.iso8601}..#{yesterday.iso8601}",
  per_page: 100
)

# Create snapshot for yesterday
snapshot = DailySnapshot.find_or_initialize_by(snapshot_date: yesterday)
snapshot.update!(
  total_prs: 71,  # Based on your logs showing 71 PRs
  approved_prs: 4,
  prs_with_changes_requested: 2,
  pending_review_prs: 20,
  draft_prs: 49,
  failing_ci_prs: 67,
  successful_ci_prs: 4,
  prs_opened_today: opened_prs.total_count,
  prs_closed_today: closed_prs.total_count,
  prs_merged_today: merged_prs.total_count
)

puts "Created snapshot for #{yesterday}: Opened: #{opened_prs.total_count}, Closed: #{closed_prs.total_count}, Merged: #{merged_prs.total_count}"

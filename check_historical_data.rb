#!/usr/bin/env ruby
require_relative 'config/environment'

puts "\n=== CHECKING HISTORICAL DATA IN DATABASE ===\n"

# Check if we have any daily snapshots
total_snapshots = DailySnapshot.count
puts "Total daily snapshots in database: #{total_snapshots}"

if total_snapshots > 0
  puts "\nAvailable snapshots:"
  puts "-" * 80

  DailySnapshot.order(snapshot_date: :desc).each do |snapshot|
    puts "Date: #{snapshot.snapshot_date}"
    puts "  - Total PRs: #{snapshot.total_prs}"
    puts "  - Approved PRs: #{snapshot.approved_prs}"
    puts "  - Pending Review PRs: #{snapshot.pending_review_prs}"
    puts "  - Draft PRs: #{snapshot.draft_prs}"
    puts "  - Failing CI PRs: #{snapshot.failing_ci_prs}"
    puts "  - Successful CI PRs: #{snapshot.successful_ci_prs}"
    puts "  - PRs opened today: #{snapshot.prs_opened_today || 0}"
    puts "  - PRs closed today: #{snapshot.prs_closed_today || 0}"
    puts "  - PRs merged today: #{snapshot.prs_merged_today || 0}"
    puts "-" * 80
  end

  # Show what the API would return for 7 days
  puts "\n\n=== SIMULATING API RESPONSE FOR /api/v1/reviews/historical?days=7 ===\n"

  snapshots = DailySnapshot.last_n_days(7)
  chart_data = snapshots.map do |snapshot|
    {
      date: snapshot.snapshot_date.to_s,
      total_prs: snapshot.total_prs,
      approved_prs: snapshot.approved_prs,
      pending_review_prs: snapshot.pending_review_prs,
      changes_requested_prs: snapshot.prs_with_changes_requested,
      draft_prs: snapshot.draft_prs,
      failing_ci_prs: snapshot.failing_ci_prs,
      successful_ci_prs: snapshot.successful_ci_prs,
      prs_opened_today: snapshot.prs_opened_today || 0,
      prs_closed_today: snapshot.prs_closed_today || 0,
      prs_merged_today: snapshot.prs_merged_today || 0
    }
  end

  api_response = {
    data: chart_data,
    period: "7 days",
    start_date: 7.days.ago.to_date.to_s,
    end_date: Date.current.to_s
  }

  puts JSON.pretty_generate(api_response)

  puts "\n\nNumber of days with data available: #{chart_data.length}"
  puts "Chart will use #{chart_data.length < 7 ? 'MOCK DATA' : 'REAL DATA'} (needs at least 7 days)"
else
  puts "\nNO HISTORICAL DATA FOUND!"
  puts "The daily snapshot job has not been running or no data has been captured yet."
end

puts "\n\n=== CHECKING CURRENT PULL REQUESTS ===\n"
puts "Total open PRs in database: #{PullRequest.open.count}"
puts "Last PR update: #{PullRequest.maximum(:updated_at)}"

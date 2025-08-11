#!/usr/bin/env ruby
# Script to populate historical daily snapshots for testing

logger = Logger.new(STDOUT)
logger.info "Populating historical data for the past 7 days"

# Get current values as a baseline
current_snapshot = DailySnapshot.last
base_total = current_snapshot&.total_prs || 75
base_approved = current_snapshot&.approved_prs || 5
base_failing = current_snapshot&.failing_ci_prs || 60

# Create snapshots for the past 6 days
6.downto(1) do |days_ago|
  date = days_ago.days.ago.to_date

  # Create slightly different values for each day
  variance = rand(-5..5)

  snapshot = DailySnapshot.find_or_create_by(snapshot_date: date)
  snapshot.update!(
    total_prs: base_total + variance,
    approved_prs: base_approved + rand(-2..2),
    prs_with_changes_requested: rand(1..5),
    pending_review_prs: rand(15..25),
    draft_prs: rand(45..55),
    failing_ci_prs: base_failing + rand(-10..10),
    successful_ci_prs: rand(2..8),
    prs_opened_today: rand(15..35),
    prs_closed_today: rand(20..40),
    prs_merged_today: rand(15..35)
  )

  logger.info "Created snapshot for #{date}: Total PRs: #{snapshot.total_prs}, Opened: #{snapshot.prs_opened_today}, Closed: #{snapshot.prs_closed_today}"
end

logger.info "Historical data populated successfully"

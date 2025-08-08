#!/usr/bin/env ruby

puts "Backfilling missing vets-api snapshots..."

# Backfill missing days for vets-api only
missing_dates = ['2025-08-05', '2025-08-07', '2025-08-08'].map(&:to_date)

missing_dates.each do |date|
  puts "Creating snapshot for #{date}..."
  
  # Use CaptureDailyMetricsJob but override the date
  snapshot = DailySnapshot.find_or_initialize_by(
    snapshot_date: date,
    repository_name: 'vets-api',
    repository_owner: 'department-of-veterans-affairs'
  )
  
  # For today, run the actual job
  if date == Date.current
    CaptureDailyMetricsJob.perform_now(
      repository_name: 'vets-api',
      repository_owner: 'department-of-veterans-affairs'
    )
  else
    # For past dates, use current counts as approximation
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
      prs_opened_today: 0,
      prs_closed_today: 0,
      prs_merged_today: 0
    )
  end
end

puts "\nVets-api now has #{DailySnapshot.where(repository_name: 'vets-api').count} snapshots"
puts "Last 7 days data available: #{DailySnapshot.where(repository_name: 'vets-api', snapshot_date: 6.days.ago.to_date..Date.current).count}"
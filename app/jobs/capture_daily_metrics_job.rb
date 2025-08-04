class CaptureDailyMetricsJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting daily metrics capture at #{Time.current}"
    
    github_service = GithubService.new
    
    # Define business hours window (6am to 6pm EST)
    now = Time.current.in_time_zone('America/New_York')
    business_day_start = now.beginning_of_day + 6.hours  # 6am EST
    business_day_end = now.beginning_of_day + 18.hours   # 6pm EST
    
    # For the GitHub API queries, use a 24-hour window
    today = Date.current
    yesterday = today - 1.day
    
    # Fetch PRs opened in the last 24 hours
    opened_prs = github_service.search_pull_requests(
      query: "repo:#{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']} is:pr created:#{yesterday.iso8601}..#{today.iso8601}",
      per_page: 100
    )
    prs_opened_today = opened_prs.total_count
    
    # Fetch PRs closed in the last 24 hours
    closed_prs = github_service.search_pull_requests(
      query: "repo:#{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']} is:pr is:closed closed:#{yesterday.iso8601}..#{today.iso8601}",
      per_page: 100
    )
    prs_closed_today = closed_prs.total_count
    
    # Fetch PRs merged in the last 24 hours
    merged_prs = github_service.search_pull_requests(
      query: "repo:#{ENV['GITHUB_OWNER']}/#{ENV['GITHUB_REPO']} is:pr is:merged merged:#{yesterday.iso8601}..#{today.iso8601}",
      per_page: 100
    )
    prs_merged_today = merged_prs.total_count
    
    # Get current open PR statistics
    total_prs = PullRequest.open.count
    
    # Count PRs by approval status
    # Count PRs that have ANY approvals (not just backend approvals)
    approved_prs = PullRequest.open.select { |pr| 
      pr.approval_summary && pr.approval_summary[:approved_count] && pr.approval_summary[:approved_count] > 0
    }.count
    
    # Also track backend approved PRs separately if needed
    backend_approved_prs = PullRequest.open.where(backend_approval_status: 'approved').count
    
    # Count PRs with changes requested
    prs_with_changes_requested = PullRequest.open.select { |pr| 
      pr.approval_summary && pr.approval_summary[:status] == 'changes_requested' 
    }.count
    
    # Count PRs by CI status
    failing_ci_prs = PullRequest.open.where(ci_status: 'failure').count
    successful_ci_prs = PullRequest.open.where(ci_status: 'success').count
    
    # Count draft PRs
    draft_prs = PullRequest.open.where(draft: true).count
    
    # Count pending review (non-draft PRs without approval)
    pending_review_prs = PullRequest.open.where(draft: false).where.not(backend_approval_status: 'approved').count
    
    # Create or update today's snapshot
    snapshot = DailySnapshot.find_or_initialize_by(snapshot_date: today)
    snapshot.update!(
      total_prs: total_prs,
      approved_prs: approved_prs,
      prs_with_changes_requested: prs_with_changes_requested,
      pending_review_prs: pending_review_prs,
      draft_prs: draft_prs,
      failing_ci_prs: failing_ci_prs,
      successful_ci_prs: successful_ci_prs,
      prs_opened_today: prs_opened_today,
      prs_closed_today: prs_closed_today,
      prs_merged_today: prs_merged_today,
      prs_approved_during_business_hours: 0, # Will be calculated below
      business_hours_start: business_day_start,
      business_hours_end: business_day_end
    )
    
    # Count PRs approved during business hours (6am-6pm EST)
    # This requires checking the approval timestamps
    prs_approved_during_business_hours = PullRequest.open.select { |pr|
      if pr.pull_request_reviews.approved.any?
        # Check if any approval happened during business hours today
        pr.pull_request_reviews.approved.any? { |review|
          review_time = review.submitted_at
          if review_time && review_time >= business_day_start && review_time <= business_day_end
            true
          else
            false
          end
        }
      else
        false
      end
    }.count
    
    # Update the snapshot with business hours approvals
    snapshot.update!(prs_approved_during_business_hours: prs_approved_during_business_hours)
    
    Rails.logger.info "Daily metrics captured successfully: " \
      "Total: #{total_prs}, Approved: #{approved_prs}, " \
      "Approved during business hours: #{prs_approved_during_business_hours}, " \
      "Opened: #{prs_opened_today}, Closed: #{prs_closed_today}, Merged: #{prs_merged_today}"
    
    snapshot
  rescue => e
    Rails.logger.error "Error capturing daily metrics: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    raise
  end
end
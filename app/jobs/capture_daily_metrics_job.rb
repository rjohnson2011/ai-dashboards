class CaptureDailyMetricsJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting daily metrics capture at #{Time.current}"
    
    github_service = GithubService.new
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
    approved_prs = PullRequest.open.where(backend_approval_status: 'approved').count
    
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
      prs_merged_today: prs_merged_today
    )
    
    Rails.logger.info "Daily metrics captured successfully: " \
      "Total: #{total_prs}, Opened: #{prs_opened_today}, " \
      "Closed: #{prs_closed_today}, Merged: #{prs_merged_today}"
    
    snapshot
  rescue => e
    Rails.logger.error "Error capturing daily metrics: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    raise
  end
end
class DailySnapshot < ApplicationRecord
  validates :snapshot_date, presence: true, uniqueness: true
  
  def self.capture_snapshot!
    today = Date.current
    
    # Get current PR statistics
    total_prs = PullRequest.open.count
    
    # Count PRs by approval status
    approved_prs = PullRequest.open.select { |pr| pr.approval_summary[:status] == 'approved' }.count
    prs_with_changes_requested = PullRequest.open.select { |pr| pr.approval_summary[:status] == 'changes_requested' }.count
    
    # Count PRs by CI status
    failing_ci_prs = PullRequest.open.select { |pr| pr.overall_status == 'failure' }.count
    successful_ci_prs = PullRequest.open.select { |pr| pr.overall_status == 'success' }.count
    
    # Count draft PRs
    draft_prs = PullRequest.open.where(draft: true).count
    
    # Count pending review (for now, all non-draft PRs)
    pending_review_prs = PullRequest.open.where(draft: false).count
    
    # Create or update today's snapshot
    snapshot = find_or_initialize_by(snapshot_date: today)
    snapshot.update!(
      total_prs: total_prs,
      approved_prs: approved_prs,
      prs_with_changes_requested: prs_with_changes_requested,
      pending_review_prs: pending_review_prs,
      draft_prs: draft_prs,
      failing_ci_prs: failing_ci_prs,
      successful_ci_prs: successful_ci_prs
    )
    
    snapshot
  end
  
  # Get snapshots for a date range
  def self.for_range(start_date, end_date)
    where(snapshot_date: start_date..end_date).order(:snapshot_date)
  end
  
  # Get last N days of snapshots
  def self.last_n_days(n)
    for_range(n.days.ago.to_date, Date.current)
  end
end
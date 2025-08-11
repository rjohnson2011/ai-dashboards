class DailySnapshot < ApplicationRecord
  validates :snapshot_date, presence: true

  # Only validate repository columns if they exist
  if column_names.include?("repository_name")
    validates :repository_name, presence: true
    validates :repository_owner, presence: true
    validates :snapshot_date, uniqueness: { scope: [ :repository_owner, :repository_name ] }
  else
    validates :snapshot_date, uniqueness: true
  end

  def self.capture_snapshot!(repository_name: nil, repository_owner: nil)
    today = Date.current
    repository_name ||= ENV["GITHUB_REPO"]
    repository_owner ||= ENV["GITHUB_OWNER"]

    # Get current PR statistics for this repository
    base_scope = if column_names.include?("repository_name") && PullRequest.column_names.include?("repository_name")
      PullRequest.where(repository_name: repository_name, repository_owner: repository_owner)
    else
      PullRequest.all
    end
    total_prs = base_scope.open.count

    # Count PRs by approval status
    approved_prs = base_scope.open.select { |pr| pr.approval_summary[:status] == "approved" }.count
    prs_with_changes_requested = base_scope.open.select { |pr| pr.approval_summary[:status] == "changes_requested" }.count

    # Count PRs by CI status
    failing_ci_prs = base_scope.open.select { |pr| pr.overall_status == "failure" }.count
    successful_ci_prs = base_scope.open.select { |pr| pr.overall_status == "success" }.count

    # Count draft PRs
    draft_prs = base_scope.open.where(draft: true).count

    # Count pending review (for now, all non-draft PRs)
    pending_review_prs = base_scope.open.where(draft: false).count

    # Create or update today's snapshot for this repository
    if column_names.include?("repository_name")
      snapshot = find_or_initialize_by(
        snapshot_date: today,
        repository_name: repository_name,
        repository_owner: repository_owner
      )
    else
      snapshot = find_or_initialize_by(snapshot_date: today)
    end

    update_attrs = {
      total_prs: total_prs,
      approved_prs: approved_prs,
      prs_with_changes_requested: prs_with_changes_requested,
      pending_review_prs: pending_review_prs,
      draft_prs: draft_prs,
      failing_ci_prs: failing_ci_prs,
      successful_ci_prs: successful_ci_prs
    }

    # Only add repository columns if they exist
    if column_names.include?("repository_name")
      update_attrs[:repository_name] = repository_name
      update_attrs[:repository_owner] = repository_owner
    end

    snapshot.update!(update_attrs)

    snapshot
  end

  # Get snapshots for a date range
  def self.for_range(start_date, end_date, repository_name: nil, repository_owner: nil)
    scope = where(snapshot_date: start_date..end_date)
    if repository_name && repository_owner
      scope = scope.where(repository_name: repository_name, repository_owner: repository_owner)
    end
    scope.order(:snapshot_date)
  end

  # Get last N days of snapshots
  def self.last_n_days(n, repository_name: nil, repository_owner: nil)
    for_range(n.days.ago.to_date, Date.current, repository_name: repository_name, repository_owner: repository_owner)
  end
end

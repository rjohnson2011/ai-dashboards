class PullRequest < ApplicationRecord
  has_many :check_runs, dependent: :destroy
  has_many :pull_request_reviews, dependent: :destroy
  has_many :pull_request_comments, dependent: :destroy

  validates :github_id, presence: true
  validates :number, presence: true

  # Only validate repository columns if they exist
  if column_names.include?("repository_name")
    validates :repository_name, presence: true
    validates :repository_owner, presence: true

    # Ensure uniqueness per repository
    validates :number, uniqueness: { scope: [ :repository_owner, :repository_name ] }
    validates :github_id, uniqueness: { scope: [ :repository_owner, :repository_name ] }
  else
    # Simple uniqueness without repository scope
    validates :number, uniqueness: true
    validates :github_id, uniqueness: true
  end
  validates :title, presence: true
  validates :author, presence: true
  validates :state, presence: true
  validates :url, presence: true

  scope :open, -> { where(state: "open") }
  scope :closed, -> { where(state: "closed") }
  scope :draft, -> { where(draft: true) }
  scope :ready, -> { where(draft: false) }
  scope :approved, -> { where.not(approved_at: nil) }
  scope :not_approved, -> { where(approved_at: nil) }

  # Lighthouse teams (lighthouse-dash, lighthouse-pivot, lighthouse-banana-peels)
  # were removed from the exemption list on Dec 1, 2025 per PR #25353
  # However, existing PRs still have the exempt-be-review label
  # This method provides the correct exemption status, ignoring the label for Lighthouse PRs
  LIGHTHOUSE_LABELS = [ "claimsApi" ].freeze

  def truly_exempt_from_backend_review?
    # If no exempt label, definitely not exempt
    return false unless labels && labels.include?("exempt-be-review")

    # If PR has Lighthouse team indicators, it's NOT exempt (policy changed Dec 1, 2025)
    return false if labels.any? { |label| LIGHTHOUSE_LABELS.include?(label) }

    # Otherwise, respect the exempt label
    true
  end

  def failing_checks
    check_runs.where(status: [ "failure", "error", "cancelled" ])
  end

  def passing_checks
    check_runs.where(status: "success")
  end

  def required_checks
    check_runs.where(required: true)
  end

  def required_failing_checks
    required_checks.where(status: [ "failure", "error", "cancelled" ])
  end

  def overall_status
    # If any required checks are failing, status is failure
    return "failure" if required_failing_checks.any?

    # If all required checks are passing, status is success
    return "success" if required_checks.any? && required_failing_checks.empty?

    # If there are no required checks, use overall check status
    return "failure" if failing_checks.any?
    return "success" if passing_checks.any?

    "pending"
  end

  def calculate_backend_approval_status
    # Reload the association to ensure we have the latest reviews from DB
    # This is necessary because destroy_all + create! doesn't clear the association cache
    pull_request_reviews.reload

    # Get the latest ACTIONABLE review from each user
    # COMMENTED reviews don't change approval state - only APPROVED, CHANGES_REQUESTED, DISMISSED do
    # This handles the case where someone approves and then comments (creates 2 review records)
    reviews_by_user = pull_request_reviews.group_by(&:user)
    latest_actionable_reviews = reviews_by_user.map do |_user, reviews|
      # First try to find the latest actionable review (not COMMENTED)
      actionable_reviews = reviews.reject { |r| r.state == PullRequestReview::COMMENTED }
      if actionable_reviews.any?
        actionable_reviews.max_by(&:submitted_at)
      else
        # If all reviews are COMMENTED, use the latest one
        reviews.max_by(&:submitted_at)
      end
    end

    # Check if any backend review group member has their latest actionable review as APPROVED
    approved_users = latest_actionable_reviews
      .select { |review| review.state == PullRequestReview::APPROVED }
      .map(&:user)

    backend_members = BackendReviewGroupMember.pluck(:username)
    backend_approved = (approved_users & backend_members).any?

    backend_approved ? "approved" : "not_approved"
  end

  def update_backend_approval_status!
    old_status = backend_approval_status
    new_status = calculate_backend_approval_status

    self.backend_approval_status = new_status

    # Track when backend approval first happens (for turnaround metrics)
    if new_status == "approved" && old_status != "approved"
      # Just became backend approved - set the timestamp
      self.backend_approved_at = Time.current
      Rails.logger.info "[PullRequest] PR ##{number} received backend approval"
    elsif new_status != "approved" && old_status == "approved"
      # Lost backend approval (e.g., new commits invalidated it) - clear timestamp
      self.backend_approved_at = nil
      Rails.logger.info "[PullRequest] PR ##{number} lost backend approval"
    end

    save!
  end

  def calculate_ready_for_backend_review
    # PR is ready for backend review if:
    # 1. All CI checks are passing (or only review-related checks are failing)
    # 2. Has at least one approval from a non-backend reviewer

    # Review-related checks that shouldn't prevent ready for backend review
    review_related_checks = [
      "Pull Request Ready for Review",
      "Danger",
      "Status Checks",
      "Get PR data",
      "Get PR Data",
      "Check Workflow Statuses",
      "Require backend-review-group approval / Get PR Data"
    ]

    # Check if we have failing checks (excluding review-related checks)
    non_review_failing_checks = if failed_checks.to_i > 0
      # Look for failing checks that are NOT review-related
      # Using the check data from cache if available
      failing_check_details = Rails.cache.read("pr_#{id}_failing_checks") || []
      failing_check_details.reject { |check|
        check_name = check[:name] || ""
        # Exclude backend-related checks
        check_name.downcase.include?("backend") ||
        # Exclude danger checks
        check_name.downcase.include?("danger") ||
        # Exclude checks in our review-related list (exact match)
        review_related_checks.include?(check_name) ||
        # Exclude checks that contain "Get PR Data" anywhere
        check_name.include?("Get PR Data") ||
        # Exclude checks that contain "Check Workflow Statuses" anywhere
        check_name.include?("Check Workflow Statuses")
      }.any?
    else
      false
    end

    # If there are non-review failing checks, not ready
    return false if non_review_failing_checks

    # Check if we have approvals from non-backend reviewers
    approved_users = pull_request_reviews
      .where(state: PullRequestReview::APPROVED)
      .pluck(:user)

    backend_members = BackendReviewGroupMember.pluck(:username)
    non_backend_approvals = approved_users - backend_members

    # Ready if we have at least one non-backend approval
    non_backend_approvals.any?
  end

  def update_ready_for_backend_review!
    new_ready_status = calculate_ready_for_backend_review

    # Track when PR becomes ready for backend review (for turnaround metrics)
    if new_ready_status && !ready_for_backend_review
      # Just became ready - set the timestamp
      self.ready_for_backend_review_at = Time.current
      Rails.logger.info "[PullRequest] PR ##{number} is now ready for backend review"
    elsif !new_ready_status && ready_for_backend_review
      # No longer ready - clear the timestamp
      self.ready_for_backend_review_at = nil
    end

    self.ready_for_backend_review = new_ready_status
    save!
  end

  def review_turnaround_seconds
    # Calculate time from ready_for_backend_review_at to backend_approved_at
    return nil unless ready_for_backend_review_at && backend_approved_at
    return nil if backend_approved_at < ready_for_backend_review_at

    (backend_approved_at - ready_for_backend_review_at).to_i
  end

  def review_turnaround_hours
    seconds = review_turnaround_seconds
    return nil unless seconds

    (seconds / 3600.0).round(1)
  end

  # Returns array of [start_time, end_time] pairs representing windows where
  # the author was addressing reviewer feedback. These should be EXCLUDED from
  # review turnaround calculations since they represent author work, not reviewer wait time.
  #
  # Logic: When a backend reviewer submits CHANGES_REQUESTED, the clock stops.
  # It restarts when any backend reviewer submits a new event (APPROVED, COMMENTED,
  # or another CHANGES_REQUESTED), indicating they've re-engaged with the PR.
  def calculate_author_feedback_windows
    backend_members = BackendReviewGroupMember.pluck(:username)

    backend_reviews = pull_request_reviews
      .where(user: backend_members)
      .where(state: [ PullRequestReview::CHANGES_REQUESTED, PullRequestReview::APPROVED,
                      PullRequestReview::COMMENTED ])
      .order(submitted_at: :asc)

    windows = []
    pending_cr_at = nil

    backend_reviews.each do |review|
      if review.state == PullRequestReview::CHANGES_REQUESTED
        # Start an excluded window (only if not already in one)
        pending_cr_at ||= review.submitted_at
      elsif pending_cr_at
        # Next backend reviewer event closes the excluded window
        windows << [ pending_cr_at, review.submitted_at ]
        pending_cr_at = nil
      end
    end

    # If dangling CHANGES_REQUESTED with no subsequent review, close at approval time
    if pending_cr_at && backend_approved_at
      windows << [ pending_cr_at, backend_approved_at ]
    end

    windows
  end

  def fully_approved?
    # A PR is fully approved when EITHER:
    # 1. All checks are passing (no failures)
    # 2. Has backend approval and only 1 failing check (assumed to be the backend check itself)
    # AND is not a draft and is open

    return false unless state == "open" && !draft && total_checks.to_i > 0

    if failed_checks.to_i == 0
      true
    elsif backend_approval_status == "approved" && failed_checks.to_i == 1
      # Check if the only failing check is the backend approval check
      # TODO: Re-enable cache after solid_cache migrations
      # failing_checks = Rails.cache.read("pr_#{id}_failing_checks") || []
      failing_checks = check_runs.where(status: [ "failure", "error", "cancelled" ]).to_a
      if failing_checks.length == 1
        check_name = failing_checks.first.name.to_s.downcase
        check_name.include?("backend") && check_name.include?("approval")
      else
        # If we don't have cache data but have backend approval and 1 failure, assume it's approved
        true
      end
    else
      false
    end
  end

  def update_approval_status!
    # Update approved_at timestamp based on current status
    if fully_approved? && approved_at.nil?
      # Just became fully approved
      self.approved_at = Time.current
      save!
      Rails.logger.info "[PullRequest] PR ##{number} is now fully approved"
    elsif !fully_approved? && approved_at.present?
      # Was approved but now has failures
      self.approved_at = nil
      save!
      Rails.logger.info "[PullRequest] PR ##{number} is no longer fully approved"
    end
  end

  def calculate_awaiting_author_changes
    # PR is awaiting author changes if:
    # 1. Someone has requested changes (CHANGES_REQUESTED state)
    # 2. AND the author hasn't pushed new commits since that review
    #
    # Once author pushes new commits, it goes back to "ready for review"

    # Get the latest CHANGES_REQUESTED review
    latest_changes_requested = pull_request_reviews
      .where(state: PullRequestReview::CHANGES_REQUESTED)
      .order(submitted_at: :desc)
      .first

    return false unless latest_changes_requested

    # Check if the reviewer who requested changes has since approved
    later_approval_from_same_user = pull_request_reviews
      .where(user: latest_changes_requested.user)
      .where(state: PullRequestReview::APPROVED)
      .where("submitted_at > ?", latest_changes_requested.submitted_at)
      .exists?

    return false if later_approval_from_same_user

    # Check if pr_updated_at is after the changes_requested review
    # This indicates the author has made updates (pushed commits, responded, etc.)
    if pr_updated_at && pr_updated_at > latest_changes_requested.submitted_at
      # PR was updated after changes were requested
      # Check if head_sha changed (indicates new commits)
      # We'll use pr_updated_at as a proxy - if it's significantly later, assume author responded
      time_since_review = pr_updated_at - latest_changes_requested.submitted_at

      # If more than 5 minutes passed and PR was updated, author likely responded
      # This is a heuristic - ideally we'd check commit timestamps
      return false if time_since_review > 5.minutes
    end

    # Still awaiting author changes
    true
  end

  def update_awaiting_author_changes!
    new_status = calculate_awaiting_author_changes
    if awaiting_author_changes != new_status
      self.awaiting_author_changes = new_status
      save!
      Rails.logger.info "[PullRequest] PR ##{number} awaiting_author_changes: #{new_status}"
    end
  end

  def has_commits_after_backend_approval?
    # Check if PR has backend approval
    return false unless backend_approval_status == "approved"

    # Get the timestamp of the last backend approval
    backend_members = BackendReviewGroupMember.pluck(:username)
    last_backend_approval = pull_request_reviews
      .where(state: PullRequestReview::APPROVED)
      .where(user: backend_members)
      .order(submitted_at: :desc)
      .first

    return false unless last_backend_approval

    # Check cache first to avoid repeated API calls
    cache_key = "pr_#{id}_commits_after_approval"
    cached_result = Rails.cache.read(cache_key)
    return cached_result unless cached_result.nil?

    # Fetch commits from GitHub
    begin
      github_service = GithubService.new(owner: repository_owner, repo: repository_name)
      commits = github_service.pull_request_commits(number)

      # Check if any commits by the PR author happened after the last backend approval
      # Exclude merge commits (merging master/main into the branch is standard practice)
      author_commits_after_approval = commits.any? do |commit|
        commit_author = commit.commit.author.name rescue commit.author&.login rescue nil
        commit_date = commit.commit.author.date rescue nil
        commit_message = commit.commit.message rescue ""

        # Skip merge commits (merging master/main into the branch)
        is_merge_commit = commit_message.downcase.start_with?("merge branch") ||
                          commit_message.downcase.start_with?("merge pull request") ||
                          commit_message.downcase.include?("merge branch 'master'") ||
                          commit_message.downcase.include?("merge branch 'main'") ||
                          commit_message.downcase.include?("merge remote-tracking branch")

        # Check if commit is by the PR author, happened after approval, and is NOT a merge commit
        (commit_author == author || commit.author&.login == author) &&
          commit_date &&
          commit_date > last_backend_approval.submitted_at &&
          !is_merge_commit
      end

      # Cache the result for 1 hour
      Rails.cache.write(cache_key, author_commits_after_approval, expires_in: 1.hour)
      author_commits_after_approval
    rescue => e
      Rails.logger.error "Error checking commits after approval for PR ##{number}: #{e.message}"
      false
    end
  end

  def changes_requested_info
    # Get backend team members
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Check for commits after backend approval (new logic)
    if has_commits_after_backend_approval?
      last_backend_approval = pull_request_reviews
        .where(state: PullRequestReview::APPROVED)
        .where(user: backend_members)
        .order(submitted_at: :desc)
        .first

      return {
        status: "new_commits_after_approval",
        message: "New commits by author",
        backend_approver: last_backend_approval.user,
        approved_at: last_backend_approval.submitted_at
      }
    end

    # Check for ANY DISMISSED reviews (indicates new commits invalidated previous approvals)
    has_dismissed_reviews = pull_request_reviews.where(state: "DISMISSED").exists?

    # If there are dismissed reviews AND current non-backend approvals AND backend has commented/reviewed,
    # this means the author pushed new commits after backend review that need re-review
    if has_dismissed_reviews
      # Check if there are current approvals from non-backend team members
      current_approvals = approval_summary
      has_non_backend_approvals = current_approvals &&
                                   current_approvals[:approved_count] > 0 &&
                                   current_approvals[:approved_users].none? { |u| backend_members.include?(u) }

      # Check if backend has reviewed (commented or changes requested) but not approved yet
      backend_has_reviewed = pull_request_reviews
        .where(user: backend_members)
        .where(state: [ "COMMENTED", "CHANGES_REQUESTED" ])
        .exists?

      backend_not_approved = backend_approval_status != "approved"

      if has_non_backend_approvals && backend_has_reviewed && backend_not_approved
        last_dismissed = pull_request_reviews.where(state: "DISMISSED").order(submitted_at: :desc).first
        return {
          status: "new_commit_from_author",
          message: "New Commit From Author",
          dismissed_at: last_dismissed.submitted_at
        }
      end
    end

    # Find the latest CHANGES_REQUESTED or COMMENTED review from a backend team member
    # We consider COMMENTED reviews as implicit change requests since reviewers often
    # leave feedback without formally requesting changes
    latest_backend_review = pull_request_reviews
      .where(user: backend_members)
      .where(state: [ "CHANGES_REQUESTED", "COMMENTED" ])
      .order(submitted_at: :desc)
      .first

    # Also check regular PR comments from backend team members
    latest_backend_comment = pull_request_comments
      .where(user: backend_members)
      .order(commented_at: :desc)
      .first

    # Pick whichever backend feedback is more recent (review or comment)
    review_time = latest_backend_review&.submitted_at
    comment_time = latest_backend_comment&.commented_at

    if comment_time && (!review_time || comment_time > review_time)
      latest_feedback_user = latest_backend_comment.user
      latest_feedback_at = latest_backend_comment.commented_at
    elsif latest_backend_review
      latest_feedback_user = latest_backend_review.user
      latest_feedback_at = latest_backend_review.submitted_at
    else
      return nil
    end

    # Check if there's been an APPROVED review from the same backend member after their feedback
    later_approval = pull_request_reviews
      .where(user: latest_feedback_user)
      .where(state: "APPROVED")
      .where("submitted_at > ?", latest_feedback_at)
      .exists?

    # If the reviewer approved after their feedback, don't show as changes requested
    return nil if later_approval

    # Check if there's a newer response from the PR author after the backend feedback
    # Look at both author reviews and author comments
    author_review_after = pull_request_reviews
      .where(user: author)
      .where("submitted_at > ?", latest_feedback_at)
      .order(submitted_at: :desc)
      .first

    author_comment_after = pull_request_comments
      .where(user: author)
      .where("commented_at > ?", latest_feedback_at)
      .order(commented_at: :desc)
      .first

    # Pick the most recent author response (review or comment)
    author_response_at = [ author_review_after&.submitted_at, author_comment_after&.commented_at ].compact.max

    if author_response_at
      {
        status: "new_comment_from_author",
        message: "Author responded",
        backend_commenter: latest_feedback_user,
        backend_comment_at: latest_feedback_at,
        author_comment_at: author_response_at
      }
    else
      {
        status: "changes_requested",
        message: "#{latest_feedback_user} at #{latest_feedback_at.in_time_zone('Eastern Time (US & Canada)').strftime('%-l:%M%p %b %-d')}",
        backend_commenter: latest_feedback_user,
        backend_comment_at: latest_feedback_at
      }
    end
  rescue => e
    Rails.logger.error "Error in changes_requested_info: #{e.message}"
    nil
  end

  # Returns the latest reviewer activity (comment or review) from non-author users
  # This shows teammate feedback like "riley commented at 3:45 PM"
  def latest_reviewer_activity
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Get latest review from non-author (prioritize changes requested)
    latest_review = pull_request_reviews
      .where.not(user: author)
      .where(state: %w[CHANGES_REQUESTED COMMENTED APPROVED])
      .order(submitted_at: :desc)
      .first

    # Get latest comment from non-author
    latest_comment = pull_request_comments
      .where.not(user: author)
      .order(commented_at: :desc)
      .first

    # Determine which is more recent
    review_time = latest_review&.submitted_at
    comment_time = latest_comment&.commented_at

    # Build activity info based on most recent
    activity = nil

    if comment_time && (!review_time || comment_time > review_time)
      # Comment is more recent
      is_backend = backend_members.include?(latest_comment.user)
      activity = {
        type: "comment",
        user: latest_comment.user,
        is_backend_reviewer: is_backend,
        timestamp: latest_comment.commented_at,
        preview: latest_comment.body&.truncate(100),
        url: build_comment_url(latest_comment.github_id)
      }
    elsif latest_review
      # Review is more recent
      is_backend = backend_members.include?(latest_review.user)
      activity = {
        type: "review",
        user: latest_review.user,
        is_backend_reviewer: is_backend,
        state: latest_review.state,
        timestamp: latest_review.submitted_at,
        url: url # Link to PR (reviews don't have direct URLs easily)
      }
    end

    return nil unless activity

    # Format the message
    time_str = activity[:timestamp].in_time_zone("Eastern Time (US & Canada)").strftime("%-l:%M%p")
    reviewer_type = activity[:is_backend_reviewer] ? "backend" : "teammate"

    {
      message: "#{activity[:user]} #{activity[:type] == 'comment' ? 'commented' : activity[:state].downcase.tr('_', ' ')} at #{time_str}",
      user: activity[:user],
      type: activity[:type],
      reviewer_type: reviewer_type,
      timestamp: activity[:timestamp],
      preview: activity[:preview],
      url: activity[:url]
    }
  rescue => e
    Rails.logger.error "Error in latest_reviewer_activity: #{e.message}"
    nil
  end

  def approval_summary
    # Reload association to ensure we have latest reviews from DB
    pull_request_reviews.reload

    # Get the latest ACTIONABLE review from each user
    # COMMENTED reviews don't change approval state - only APPROVED, CHANGES_REQUESTED, DISMISSED do
    reviews_by_user = pull_request_reviews.group_by(&:user)
    latest_actionable_reviews = reviews_by_user.map do |_user, reviews|
      actionable_reviews = reviews.reject { |r| r.state == PullRequestReview::COMMENTED }
      if actionable_reviews.any?
        actionable_reviews.max_by(&:submitted_at)
      else
        reviews.max_by(&:submitted_at)
      end
    end

    approved_users = []
    changes_requested_users = []
    commented_users = []

    latest_actionable_reviews.each do |review|
      case review.state
      when PullRequestReview::APPROVED
        approved_users << review.user
      when PullRequestReview::CHANGES_REQUESTED
        changes_requested_users << review.user
      when PullRequestReview::COMMENTED
        commented_users << review.user
      end
    end

    # Determine overall status
    status = if changes_requested_users.any?
      "changes_requested"
    elsif approved_users.any? && changes_requested_users.empty?
      "approved"
    elsif approved_users.any?
      "partially_approved"
    else
      "pending"
    end

    {
      status: status,
      approved_count: approved_users.count,
      changes_requested_count: changes_requested_users.count,
      pending_count: 0, # We don't track pending reviews
      approved_users: approved_users,
      changes_requested_users: changes_requested_users,
      commented_users: commented_users,
      pending_users: [],
      pending_teams: []
    }
  end

  private

  def build_comment_url(comment_github_id)
    # GitHub comment URL format: https://github.com/{owner}/{repo}/pull/{number}#issuecomment-{id}
    "https://github.com/#{repository_owner}/#{repository_name}/pull/#{number}#issuecomment-#{comment_github_id}"
  end
end

class PullRequest < ApplicationRecord
  has_many :check_runs, dependent: :destroy
  has_many :pull_request_reviews, dependent: :destroy

  validates :github_id, presence: true
  validates :number, presence: true
  validates :repository_name, presence: true
  validates :repository_owner, presence: true

  # Ensure uniqueness per repository
  validates :number, uniqueness: { scope: [ :repository_owner, :repository_name ] }
  validates :github_id, uniqueness: { scope: [ :repository_owner, :repository_name ] }
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
    # Check if any backend review group member has approved
    approved_users = pull_request_reviews
      .where(state: PullRequestReview::APPROVED)
      .pluck(:user)

    backend_members = BackendReviewGroupMember.pluck(:username)
    backend_approved = (approved_users & backend_members).any?

    backend_approved ? "approved" : "not_approved"
  end

  def update_backend_approval_status!
    self.backend_approval_status = calculate_backend_approval_status
    save!
  end

  def calculate_ready_for_backend_review
    # PR is ready for backend review if:
    # 1. All CI checks are passing (or only backend review check is failing)
    # 2. Has at least one approval from a non-backend reviewer

    # Check if we have failing checks (excluding backend review check)
    non_backend_failing_checks = if failed_checks.to_i > 0
      # Look for failing checks that are NOT the backend review check
      # Using the check data from cache if available
      failing_check_details = Rails.cache.read("pr_#{id}_failing_checks") || []
      failing_check_details.reject { |check|
        check[:name]&.downcase&.include?("backend") &&
        check[:name]&.downcase&.include?("approval")
      }.any?
    else
      false
    end

    # If there are non-backend failing checks, not ready
    return false if non_backend_failing_checks

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
    self.ready_for_backend_review = calculate_ready_for_backend_review
    save!
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

  def approval_summary
    # Get the latest review from each user
    reviews_by_user = pull_request_reviews.group_by(&:user)
    latest_reviews = reviews_by_user.map { |user, reviews| reviews.max_by(&:submitted_at) }

    approved_users = []
    changes_requested_users = []
    commented_users = []

    latest_reviews.each do |review|
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
end

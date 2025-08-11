class BackendReviewGroupMember < ApplicationRecord
  validates :username, presence: true, uniqueness: true

  # Add callback to update PRs when members change
  after_create :update_pull_request_approvals
  after_destroy :update_pull_request_approvals

  def self.member?(username)
    exists?(username: username)
  end

  def self.refresh_members(members)
    transaction do
      # Remove members no longer in the group
      where.not(username: members.map { |m| m[:username] }).destroy_all

      # Add or update current members
      members.each do |member|
        find_or_initialize_by(username: member[:username]).update!(
          avatar_url: member[:avatar_url],
          fetched_at: Time.current
        )
      end
    end

    # Update all PR backend approval statuses after membership changes
    update_all_pr_approvals
  end

  def self.update_all_pr_approvals
    Rails.logger.info "Updating backend approval status for all open PRs..."
    PullRequest.open.includes(:pull_request_reviews).find_each do |pr|
      pr.update_backend_approval_status!
    end
    Rails.logger.info "Finished updating backend approval statuses"
  end

  private

  def update_pull_request_approvals
    self.class.update_all_pr_approvals
  end
end

class PullRequestReview < ApplicationRecord
  belongs_to :pull_request
  
  validates :github_id, presence: true, uniqueness: true
  validates :user, presence: true
  validates :state, presence: true
  
  # Review states
  APPROVED = 'APPROVED'
  CHANGES_REQUESTED = 'CHANGES_REQUESTED'
  COMMENTED = 'COMMENTED'
  PENDING = 'PENDING'
  DISMISSED = 'DISMISSED'
  
  scope :approved, -> { where(state: APPROVED) }
  scope :changes_requested, -> { where(state: CHANGES_REQUESTED) }
  scope :commented, -> { where(state: COMMENTED) }
  scope :pending, -> { where(state: PENDING) }
  
  # Get the latest review from each unique user
  def self.latest_per_user
    # Group by user and get the one with the latest submitted_at
    grouped = group_by(&:user)
    grouped.map { |_user, reviews| reviews.max_by(&:submitted_at) }
  end
end
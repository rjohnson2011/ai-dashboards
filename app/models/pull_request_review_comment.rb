class PullRequestReviewComment < ApplicationRecord
  belongs_to :pull_request

  validates :github_id, presence: true, uniqueness: true
  validates :user, presence: true
  validates :commented_at, presence: true

  scope :by_backend_team, -> {
    backend_members = BackendReviewGroupMember.pluck(:username)
    where(user: backend_members)
  }

  scope :ordered, -> { order(commented_at: :asc) }
end

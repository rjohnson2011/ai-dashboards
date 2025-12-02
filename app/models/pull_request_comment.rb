class PullRequestComment < ApplicationRecord
  belongs_to :pull_request

  validates :github_id, presence: true, uniqueness: true
  validates :user, presence: true
  validates :commented_at, presence: true

  scope :by_backend_team, -> {
    backend_members = BackendReviewGroupMember.pluck(:username)
    where(user: backend_members)
  }

  scope :by_author, ->(author) { where(user: author) }
  scope :ordered, -> { order(commented_at: :asc) }
end

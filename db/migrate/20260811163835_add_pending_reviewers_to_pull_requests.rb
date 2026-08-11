class AddPendingReviewersToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :pending_reviewers, :jsonb, default: []
    add_column :pull_requests, :pending_teams, :jsonb, default: []
  end
end

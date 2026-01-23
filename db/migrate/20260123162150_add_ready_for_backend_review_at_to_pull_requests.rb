class AddReadyForBackendReviewAtToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :ready_for_backend_review_at, :datetime
    add_index :pull_requests, :ready_for_backend_review_at
  end
end

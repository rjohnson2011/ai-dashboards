class AddReadyForBackendReviewToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :ready_for_backend_review, :boolean, default: false
  end
end

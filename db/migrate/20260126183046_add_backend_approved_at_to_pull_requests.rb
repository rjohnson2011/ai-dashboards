class AddBackendApprovedAtToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :backend_approved_at, :datetime
  end
end

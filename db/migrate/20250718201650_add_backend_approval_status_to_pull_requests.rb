class AddBackendApprovalStatusToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :backend_approval_status, :string, default: 'not_approved'
    add_index :pull_requests, :backend_approval_status
  end
end

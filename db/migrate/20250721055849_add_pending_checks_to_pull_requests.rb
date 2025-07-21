class AddPendingChecksToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :pending_checks, :integer, default: 0
  end
end

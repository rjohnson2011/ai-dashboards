class AddApprovedAtToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :approved_at, :datetime
  end
end

class AddAwaitingAuthorChangesToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :awaiting_author_changes, :boolean, default: false
    add_index :pull_requests, :awaiting_author_changes
  end
end

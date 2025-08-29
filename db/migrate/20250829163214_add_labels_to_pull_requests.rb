class AddLabelsToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :labels, :jsonb, default: []
    add_index :pull_requests, :labels, using: :gin
  end
end

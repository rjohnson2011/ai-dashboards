class AddHeadShaToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :head_sha, :string
    add_index :pull_requests, :head_sha
  end
end

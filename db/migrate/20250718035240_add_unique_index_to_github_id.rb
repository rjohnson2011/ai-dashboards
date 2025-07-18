class AddUniqueIndexToGithubId < ActiveRecord::Migration[8.0]
  def change
    # Remove any existing index first
    remove_index :pull_requests, :github_id if index_exists?(:pull_requests, :github_id)
    
    # Add unique index on github_id
    add_index :pull_requests, :github_id, unique: true
  end
end

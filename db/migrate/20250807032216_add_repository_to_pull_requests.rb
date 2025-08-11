class AddRepositoryToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :repository_name, :string
    add_column :pull_requests, :repository_owner, :string

    # Add indexes for querying by repository
    add_index :pull_requests, [ :repository_owner, :repository_name ]
    add_index :pull_requests, :repository_name
  end
end

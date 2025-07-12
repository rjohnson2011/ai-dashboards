class ChangeGithubIdToBigint < ActiveRecord::Migration[8.0]
  def change
    change_column :pull_requests, :github_id, :bigint
  end
end

class CreatePullRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :pull_requests do |t|
      t.integer :github_id
      t.integer :number
      t.string :title
      t.string :author
      t.string :state
      t.boolean :draft
      t.string :url
      t.datetime :pr_created_at
      t.datetime :pr_updated_at
      t.string :ci_status
      t.integer :total_checks
      t.integer :successful_checks
      t.integer :failed_checks

      t.timestamps
    end

    add_index :pull_requests, :github_id, unique: true
    add_index :pull_requests, :number, unique: true
    add_index :pull_requests, :state
    add_index :pull_requests, :ci_status
  end
end

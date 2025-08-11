class CreatePullRequestReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :pull_request_reviews do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.bigint :github_id
      t.string :user
      t.string :state # APPROVED, CHANGES_REQUESTED, COMMENTED, PENDING
      t.text :body
      t.datetime :submitted_at

      t.timestamps
    end

    add_index :pull_request_reviews, :github_id, unique: true
    add_index :pull_request_reviews, :state
  end
end

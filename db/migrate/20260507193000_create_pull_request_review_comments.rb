class CreatePullRequestReviewComments < ActiveRecord::Migration[8.0]
  def change
    create_table :pull_request_review_comments do |t|
      t.bigint :pull_request_id, null: false
      t.bigint :github_id, null: false
      t.bigint :pull_request_review_id
      t.string :user, null: false
      t.text :body
      t.string :path
      t.integer :line
      t.datetime :commented_at, null: false
      t.timestamps
    end

    add_index :pull_request_review_comments, :github_id, unique: true
    add_index :pull_request_review_comments, :pull_request_id
    add_index :pull_request_review_comments, [ :pull_request_id, :commented_at ]
  end
end

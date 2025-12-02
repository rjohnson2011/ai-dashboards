class CreatePullRequestComments < ActiveRecord::Migration[8.0]
  def change
    create_table :pull_request_comments do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.bigint :github_id, null: false
      t.string :user, null: false
      t.text :body
      t.datetime :commented_at, null: false

      t.timestamps
    end

    add_index :pull_request_comments, :github_id, unique: true
    add_index :pull_request_comments, [ :pull_request_id, :commented_at ]
  end
end

class CreateReviewEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :review_events do |t|
      t.bigint :github_id, null: false
      t.string :reviewer, null: false
      t.string :state, null: false
      t.datetime :submitted_at, null: false
      t.integer :pr_number
      t.string :repository_name
      t.string :repository_owner
      t.timestamps
    end

    add_index :review_events, :github_id, unique: true
    add_index :review_events, :submitted_at
    add_index :review_events, [ :reviewer, :submitted_at ]
  end
end

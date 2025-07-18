class CreateBackendReviewGroupMembers < ActiveRecord::Migration[8.0]
  def change
    create_table :backend_review_group_members do |t|
      t.string :username
      t.string :avatar_url
      t.datetime :fetched_at

      t.timestamps
    end
    add_index :backend_review_group_members, :username
  end
end

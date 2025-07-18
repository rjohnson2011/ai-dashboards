class CreateDailySnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :daily_snapshots do |t|
      t.date :snapshot_date, null: false
      t.integer :total_prs, default: 0
      t.integer :approved_prs, default: 0
      t.integer :prs_with_changes_requested, default: 0
      t.integer :pending_review_prs, default: 0
      t.integer :draft_prs, default: 0
      t.integer :failing_ci_prs, default: 0
      t.integer :successful_ci_prs, default: 0
      
      t.timestamps
    end
    
    add_index :daily_snapshots, :snapshot_date, unique: true
  end
end

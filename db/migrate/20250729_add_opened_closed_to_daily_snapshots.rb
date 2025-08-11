class AddOpenedClosedToDailySnapshots < ActiveRecord::Migration[8.0]
  def change
    add_column :daily_snapshots, :prs_opened_today, :integer, default: 0
    add_column :daily_snapshots, :prs_closed_today, :integer, default: 0
    add_column :daily_snapshots, :prs_merged_today, :integer, default: 0
  end
end

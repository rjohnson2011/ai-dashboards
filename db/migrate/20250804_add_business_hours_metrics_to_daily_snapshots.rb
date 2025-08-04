class AddBusinessHoursMetricsToDailySnapshots < ActiveRecord::Migration[7.1]
  def change
    add_column :daily_snapshots, :prs_approved_during_business_hours, :integer, default: 0
    add_column :daily_snapshots, :business_hours_start, :datetime
    add_column :daily_snapshots, :business_hours_end, :datetime
  end
end
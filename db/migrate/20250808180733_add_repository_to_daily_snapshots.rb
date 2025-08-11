class AddRepositoryToDailySnapshots < ActiveRecord::Migration[8.0]
  def change
    add_column :daily_snapshots, :repository_name, :string
    add_column :daily_snapshots, :repository_owner, :string

    # Add indexes for better query performance
    add_index :daily_snapshots, [ :repository_owner, :repository_name ]
    add_index :daily_snapshots, :repository_name

    # Update unique constraint to include repository
    remove_index :daily_snapshots, :snapshot_date
    add_index :daily_snapshots, [ :snapshot_date, :repository_owner, :repository_name ],
              unique: true,
              name: 'index_daily_snapshots_on_date_and_repository'
  end
end

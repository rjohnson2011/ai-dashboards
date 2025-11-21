class CreateSupportRotations < ActiveRecord::Migration[8.0]
  def change
    create_table :support_rotations do |t|
      t.integer :sprint_number
      t.string :engineer_name
      t.date :start_date
      t.date :end_date
      t.string :repository_name
      t.string :repository_owner

      t.timestamps
    end

    add_index :support_rotations, :sprint_number
    add_index :support_rotations, [:repository_name, :repository_owner]
    add_index :support_rotations, [:start_date, :end_date]
  end
end

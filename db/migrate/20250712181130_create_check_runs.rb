class CreateCheckRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :check_runs do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.string :name
      t.string :status
      t.string :url
      t.text :description
      t.boolean :required
      t.string :suite_name

      t.timestamps
    end

    add_index :check_runs, [ :pull_request_id, :suite_name ]
    add_index :check_runs, :status
    add_index :check_runs, :required
  end
end

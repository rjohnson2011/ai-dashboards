class CreateLoginEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :login_events do |t|
      t.string :email, null: false
      t.string :name
      t.string :picture
      t.datetime :logged_in_at, null: false
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :login_events, :email
    add_index :login_events, :logged_in_at
    add_index :login_events, [ :email, :logged_in_at ]
  end
end

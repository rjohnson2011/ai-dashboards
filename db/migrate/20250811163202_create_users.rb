class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.bigint :github_id
      t.string :github_username
      t.string :email
      t.string :name
      t.string :avatar_url
      t.boolean :is_va_member, default: false, null: false
      t.datetime :last_login_at
      t.text :access_token_encrypted

      t.timestamps
    end
    add_index :users, :github_id, unique: true
    add_index :users, :github_username, unique: true
  end
end

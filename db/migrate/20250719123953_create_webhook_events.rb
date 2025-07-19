class CreateWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_events do |t|
      t.string :event_type
      t.string :github_delivery_id
      t.text :payload
      t.string :status
      t.text :error_message
      t.datetime :processed_at

      t.timestamps
    end
  end
end

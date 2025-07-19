class CreateCronJobLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :cron_job_logs do |t|
      t.string :status
      t.datetime :started_at
      t.datetime :completed_at
      t.string :error_class
      t.text :error_message
      t.text :error_backtrace
      t.integer :prs_processed
      t.integer :prs_updated

      t.timestamps
    end
  end
end

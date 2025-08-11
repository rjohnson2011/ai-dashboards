class CaptureDailySnapshotJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting daily snapshot capture..."

    snapshot = DailySnapshot.capture_snapshot!

    Rails.logger.info "Daily snapshot captured successfully: #{snapshot.snapshot_date} - Total PRs: #{snapshot.total_prs}, Approved: #{snapshot.approved_prs}"
  rescue => e
    Rails.logger.error "Failed to capture daily snapshot: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end

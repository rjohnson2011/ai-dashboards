class CaptureAllDailyMetricsJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[CaptureAllDailyMetricsJob] Starting daily metrics capture for all repositories at #{Time.current}"
    
    successful_captures = 0
    failed_captures = 0
    
    RepositoryConfig.all.each do |repo|
      Rails.logger.info "[CaptureAllDailyMetricsJob] Capturing metrics for #{repo.full_name}"
      
      begin
        CaptureDailyMetricsJob.perform_now(
          repository_name: repo.name,
          repository_owner: repo.owner
        )
        successful_captures += 1
        Rails.logger.info "[CaptureAllDailyMetricsJob] Successfully captured metrics for #{repo.full_name}"
      rescue => e
        failed_captures += 1
        Rails.logger.error "[CaptureAllDailyMetricsJob] Failed to capture metrics for #{repo.full_name}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
    end
    
    Rails.logger.info "[CaptureAllDailyMetricsJob] Completed. Successful: #{successful_captures}, Failed: #{failed_captures}"
  end
end
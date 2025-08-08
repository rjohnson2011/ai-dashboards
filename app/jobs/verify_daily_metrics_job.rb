class VerifyDailyMetricsJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[VerifyDailyMetricsJob] Starting daily metrics verification at #{Time.current}"
    
    today = Date.current
    repositories_missing_metrics = []
    
    # Check each repository for today's snapshot
    RepositoryConfig.all.each do |repo|
      existing_snapshot = DailySnapshot.find_by(
        snapshot_date: today,
        repository_name: repo.name,
        repository_owner: repo.owner
      )
      
      if existing_snapshot.nil?
        repositories_missing_metrics << repo
        Rails.logger.warn "[VerifyDailyMetricsJob] Missing snapshot for #{repo.full_name} on #{today}"
      else
        Rails.logger.info "[VerifyDailyMetricsJob] Snapshot exists for #{repo.full_name} on #{today}"
      end
    end
    
    # Capture metrics for any missing repositories
    if repositories_missing_metrics.any?
      Rails.logger.info "[VerifyDailyMetricsJob] Capturing metrics for #{repositories_missing_metrics.length} repositories"
      
      repositories_missing_metrics.each do |repo|
        Rails.logger.info "[VerifyDailyMetricsJob] Capturing metrics for #{repo.full_name}"
        
        begin
          CaptureDailyMetricsJob.perform_now(
            repository_name: repo.name,
            repository_owner: repo.owner
          )
          Rails.logger.info "[VerifyDailyMetricsJob] Successfully captured metrics for #{repo.full_name}"
        rescue => e
          Rails.logger.error "[VerifyDailyMetricsJob] Failed to capture metrics for #{repo.full_name}: #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")
        end
      end
    else
      Rails.logger.info "[VerifyDailyMetricsJob] All repositories have metrics for today"
    end
    
    # Log summary
    total_repos = RepositoryConfig.all.count
    successful_repos = DailySnapshot.where(snapshot_date: today).distinct.count(:repository_name)
    
    Rails.logger.info "[VerifyDailyMetricsJob] Verification complete. #{successful_repos}/#{total_repos} repositories have metrics for #{today}"
    
    # Send alert if any repositories are still missing metrics
    final_missing = RepositoryConfig.all.select do |repo|
      !DailySnapshot.exists?(
        snapshot_date: today,
        repository_name: repo.name,
        repository_owner: repo.owner
      )
    end
    
    if final_missing.any?
      Rails.logger.error "[VerifyDailyMetricsJob] ALERT: Still missing metrics for: #{final_missing.map(&:full_name).join(', ')}"
    end
  end
end
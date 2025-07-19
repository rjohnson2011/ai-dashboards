class FetchPullRequestChecksJob < ApplicationJob
  queue_as :default
  
  def perform(pull_request_id)
    pr = PullRequest.find(pull_request_id)
    
    Rails.logger.info "[FetchPullRequestChecksJob] Updating checks for PR ##{pr.number}"
    
    # Use the scraper service to get check details
    scraper = EnhancedGithubScraperService.new
    result = scraper.scrape_pr_checks_detailed(pr.url)
    
    # Update PR with check counts
    pr.update!(
      ci_status: result[:overall_status] || 'unknown',
      total_checks: result[:total_checks] || 0,
      successful_checks: result[:successful_checks] || 0,
      failed_checks: result[:failed_checks] || 0
    )
    
    # Store failing checks in cache
    if result[:failed_checks] > 0 && result[:checks].any?
      failing_checks = result[:checks].select { |c| ['failure', 'error', 'cancelled'].include?(c[:status]) }
      Rails.cache.write("pr_#{pr.id}_failing_checks", failing_checks, expires_in: 1.hour)
    else
      Rails.cache.delete("pr_#{pr.id}_failing_checks")
    end
    
    # Clear existing check runs and save new ones
    pr.check_runs.destroy_all
    result[:checks].each do |check|
      pr.check_runs.create!(
        name: check[:name],
        status: check[:status] || 'unknown',
        url: check[:url],
        description: check[:description],
        required: check[:required] || false,
        suite_name: check[:suite_name]
      )
    end
    
    # Update ready for backend review status
    pr.update_ready_for_backend_review!
    
    # Update approval status
    pr.update_approval_status!
    
    # Update cache timestamp
    Rails.cache.write('last_refresh_time', Time.current)
    
    Rails.logger.info "[FetchPullRequestChecksJob] Successfully updated PR ##{pr.number}"
    
  rescue => e
    Rails.logger.error "[FetchPullRequestChecksJob] Error updating PR ##{pr.number}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise to trigger retry
  end
end
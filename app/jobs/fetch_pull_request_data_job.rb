class FetchPullRequestDataJob < ApplicationJob
  queue_as :default

  # Ensure only one instance of this job runs at a time
  # This prevents duplicate records from concurrent job execution
  def perform
    # Try to acquire a lock
    lock_key = 'fetch_pull_request_data_job_lock'
    lock_acquired = Rails.cache.write(lock_key, true, unless_exist: true, expires_in: 30.minutes)
    
    unless lock_acquired
      Rails.logger.info "Another instance of FetchPullRequestDataJob is already running. Skipping."
      return
    end
    
    begin
      perform_fetch
    ensure
      # Always release the lock when done
      Rails.cache.delete(lock_key)
    end
  end
  
  private
  
  def perform_fetch
    Rails.logger.info "Starting to fetch pull request data..."
    
    # Set initial refresh status
    Rails.cache.write('refresh_status', {
      updating: true,
      progress: { current: 0, total: 0 }
    })
    
    # Initialize progress counter
    Rails.cache.write('refresh_progress_counter', 0)
    
    github_service = GithubService.new
    scraper_service = EnhancedGithubScraperService.new
    
    begin
      # Fetch all open PRs from GitHub API
      pull_requests = github_service.all_pull_requests(state: 'open')
      
      Rails.logger.info "Found #{pull_requests.count} open PRs to process"
      
      # Update progress with total count
      Rails.cache.write('refresh_status', {
        updating: true,
        progress: { current: 0, total: pull_requests.count }
      })
      
      pull_requests.each_with_index do |pr, index|
        Rails.logger.info "Processing PR ##{pr.number}: #{pr.title} (#{index + 1}/#{pull_requests.count})"
        
        begin
          # Use a transaction with a lock to handle concurrent updates
          PullRequest.transaction do
            # Try to find existing record with a lock
            pr_record = PullRequest.where(github_id: pr.id).lock.first
            
            # If not found, create a new one
            pr_record ||= PullRequest.new(github_id: pr.id)
            
            # Update PR basic info
            pr_record.assign_attributes(
              number: pr.number,
              title: pr.title,
              author: pr.user.login,
              state: pr.state,
              draft: pr.draft,
              url: pr.html_url,
              pr_created_at: pr.created_at,
              pr_updated_at: pr.updated_at
            )
            
            # Scrape CI checks
            checks_data = scraper_service.scrape_pr_checks_detailed(pr.html_url)
            
            # Update PR with CI status
            pr_record.assign_attributes(
              ci_status: checks_data[:overall_status],
              total_checks: checks_data[:total_checks],
              successful_checks: checks_data[:successful_checks],
              failed_checks: checks_data[:failed_checks]
            )
            
            pr_record.save!
            
            # Clear existing check runs and create new ones
            pr_record.check_runs.destroy_all
            
            checks_data[:checks].each do |check|
              pr_record.check_runs.create!(
                name: check[:name],
                status: check[:status],
                url: check[:url],
                description: check[:description],
                required: check[:required],
                suite_name: check[:suite_name]
              )
            end
            
            Rails.logger.info "Successfully processed PR ##{pr.number} - Status: #{checks_data[:overall_status]}, Checks: #{checks_data[:total_checks]}"
          end # end transaction
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.warn "Skipping PR ##{pr.number} due to validation error: #{e.message}"
          # Skip this PR and continue with the next one
          next
        rescue ActiveRecord::RecordNotUnique => e
          Rails.logger.warn "Skipping PR ##{pr.number} due to duplicate: #{e.message}"
          # Skip this PR and continue with the next one
          next
        end
        
        # Atomically increment progress counter
        current_progress = Rails.cache.increment('refresh_progress_counter', 1) || 1
        
        # Update progress status
        Rails.cache.write('refresh_status', {
          updating: true,
          progress: { current: current_progress, total: pull_requests.count }
        })
      end
      
      Rails.logger.info "Finished fetching pull request data for #{pull_requests.count} PRs"
      
      # Mark refresh as complete
      Rails.cache.write('refresh_status', {
        updating: false,
        progress: { current: pull_requests.count, total: pull_requests.count }
      })
      
      # Store the actual refresh completion time
      Rails.cache.write('last_refresh_time', Time.current)
      
      # Clean up progress counter
      Rails.cache.delete('refresh_progress_counter')
      
    rescue => e
      Rails.logger.error "Error in FetchPullRequestDataJob: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Mark refresh as failed
      Rails.cache.write('refresh_status', {
        updating: false,
        progress: { current: 0, total: 0 }
      })
      
      # Store the refresh attempt time even on failure
      Rails.cache.write('last_refresh_time', Time.current)
      
      # Clean up progress counter
      Rails.cache.delete('refresh_progress_counter')
      
      raise e
    end
  end
end

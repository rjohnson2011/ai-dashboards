class FetchPullRequestDataOptimizedJob < ApplicationJob
  queue_as :default

  # Process PRs in smaller batches
  BATCH_SIZE = 10

  def perform(batch_number = 0)
    # Try to acquire a lock
    lock_key = "fetch_pull_request_data_job_lock"
    lock_acquired = Rails.cache.write(lock_key, true, unless_exist: true, expires_in: 30.minutes)

    unless lock_acquired
      Rails.logger.info "Another instance of FetchPullRequestDataJob is already running. Skipping."
      return
    end

    begin
      perform_batch(batch_number)
    ensure
      # Always release the lock when done
      Rails.cache.delete(lock_key)
    end
  end

  private

  def perform_batch(batch_number)
    Rails.logger.info "Starting to fetch pull request data (batch #{batch_number})..."

    github_service = GithubService.new
    scraper_service = EnhancedGithubScraperService.new

    begin
      # Fetch all open PRs from GitHub API
      all_prs = github_service.all_pull_requests(state: "open")

      # Calculate batch range
      start_index = batch_number * BATCH_SIZE
      end_index = start_index + BATCH_SIZE - 1
      pull_requests = all_prs[start_index..end_index]

      # If no PRs in this batch, we're done
      if pull_requests.nil? || pull_requests.empty?
        Rails.logger.info "No PRs to process in batch #{batch_number}"

        # Mark refresh as complete if this was the first batch with no PRs
        if batch_number == 0
          Rails.cache.write("refresh_status", {
            updating: false,
            progress: { current: 0, total: 0 }
          })
        end
        return
      end

      Rails.logger.info "Processing #{pull_requests.count} PRs in batch #{batch_number} (#{start_index + 1}-#{end_index + 1} of #{all_prs.count})"

      # Update progress for the entire job
      if batch_number == 0
        Rails.cache.write("refresh_status", {
          updating: true,
          progress: { current: 0, total: all_prs.count }
        })
        Rails.cache.write("refresh_progress_counter", 0)
      end

      # Process this batch
      pull_requests.each do |pr|
        process_single_pr(pr, github_service, scraper_service)

        # Update progress
        current_progress = Rails.cache.increment("refresh_progress_counter", 1) || 1
        Rails.cache.write("refresh_status", {
          updating: true,
          progress: { current: current_progress, total: all_prs.count }
        })
      end

      # Queue the next batch if there are more PRs
      if end_index < all_prs.count - 1
        Rails.logger.info "Queueing next batch (#{batch_number + 1})"
        FetchPullRequestDataOptimizedJob.perform_later(batch_number + 1)
      else
        # All batches complete
        Rails.logger.info "All batches complete! Processed #{all_prs.count} PRs"

        Rails.cache.write("refresh_status", {
          updating: false,
          progress: { current: all_prs.count, total: all_prs.count }
        })
        Rails.cache.write("last_refresh_time", Time.current)
        Rails.cache.delete("refresh_progress_counter")
      end

    rescue => e
      Rails.logger.error "Error in FetchPullRequestDataOptimizedJob: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Mark refresh as failed
      Rails.cache.write("refresh_status", {
        updating: false,
        progress: { current: 0, total: 0 }
      })
      Rails.cache.write("last_refresh_time", Time.current)
      Rails.cache.delete("refresh_progress_counter")

      raise e
    end
  end

  def process_single_pr(pr, github_service, scraper_service)
    Rails.logger.info "Processing PR ##{pr.number}: #{pr.title}"

    begin
      PullRequest.transaction do
        pr_record = PullRequest.where(github_id: pr.id).lock.first
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

        # Scrape CI checks with timeout
        begin
          Timeout.timeout(15) do
            checks_data = scraper_service.scrape_pr_checks_detailed(pr.html_url)

            pr_record.assign_attributes(
              ci_status: checks_data[:overall_status],
              total_checks: checks_data[:total_checks],
              successful_checks: checks_data[:successful_checks],
              failed_checks: checks_data[:failed_checks]
            )

            pr_record.save!

            # Update check runs
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
          end
        rescue Timeout::Error => e
          Rails.logger.warn "Timeout scraping checks for PR ##{pr.number}, using API only"
          pr_record.ci_status = "unknown"
          pr_record.save!
        end

        # Fetch reviews (quick API call)
        begin
          reviews = github_service.pull_request_reviews(pr.number)
          pr_record.pull_request_reviews.destroy_all

          reviews.each do |review|
            next unless review.state.present?

            pr_record.pull_request_reviews.create!(
              github_id: review.id,
              user: review.user.login,
              state: review.state,
              body: review.body,
              submitted_at: review.submitted_at
            )
          end

          pr_record.update_backend_approval_status!
        rescue => e
          Rails.logger.error "Failed to fetch reviews for PR ##{pr.number}: #{e.message}"
        end

        Rails.logger.info "Successfully processed PR ##{pr.number}"
      end
    rescue => e
      Rails.logger.warn "Error processing PR ##{pr.number}: #{e.message}"
    end
  end
end

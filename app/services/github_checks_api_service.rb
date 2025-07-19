require 'octokit'

class GithubChecksApiService
  def initialize
    @client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
    @owner = ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs'
    @repo = ENV['GITHUB_REPO'] || 'vets-api'
  end
  
  def fetch_pr_checks(pr_number)
    Rails.logger.info "[GithubChecksAPI] Fetching checks for PR ##{pr_number}"
    
    # Get the PR to find the head SHA
    pr = @client.pull_request("#{@owner}/#{@repo}", pr_number)
    head_sha = pr.head.sha
    
    # Get check runs for this SHA
    check_runs_response = @client.check_runs_for_ref("#{@owner}/#{@repo}", head_sha, per_page: 100)
    check_runs = check_runs_response.check_runs
    
    # Get check suites for additional context
    check_suites_response = @client.check_suites_for_ref("#{@owner}/#{@repo}", head_sha, per_page: 100)
    check_suites = check_suites_response.check_suites
    
    # Count statuses
    total_checks = check_runs.length
    successful_checks = check_runs.count { |run| run.status == 'completed' && run.conclusion == 'success' }
    failed_checks = check_runs.count { |run| run.status == 'completed' && ['failure', 'cancelled', 'timed_out'].include?(run.conclusion) }
    pending_checks = check_runs.count { |run| run.status != 'completed' || run.conclusion == 'neutral' }
    skipped_checks = check_runs.count { |run| run.status == 'completed' && run.conclusion == 'skipped' }
    
    # Determine overall status
    overall_status = if failed_checks > 0
      'failure'
    elsif pending_checks > 0
      'pending'
    elsif successful_checks == total_checks
      'success'
    else
      'pending'
    end
    
    # Get failing check details
    failing_checks = check_runs
      .select { |run| run.status == 'completed' && ['failure', 'cancelled', 'timed_out'].include?(run.conclusion) }
      .map do |run|
        {
          name: run.name,
          status: 'failure',
          url: run.html_url,
          description: run.output&.title,
          required: false # We'll need to determine this from branch protection rules
        }
      end
    
    Rails.logger.info "[GithubChecksAPI] PR ##{pr_number} - Total: #{total_checks}, Success: #{successful_checks}, Failed: #{failed_checks}, Pending: #{pending_checks}, Skipped: #{skipped_checks}"
    
    {
      overall_status: overall_status,
      total_checks: total_checks,
      successful_checks: successful_checks,
      failed_checks: failed_checks,
      pending_checks: pending_checks,
      skipped_checks: skipped_checks,
      failing_checks: failing_checks,
      check_runs: check_runs
    }
  rescue Octokit::TooManyRequests => e
    Rails.logger.warn "[GithubChecksAPI] Rate limited for PR ##{pr_number}. Waiting 60 seconds..."
    sleep(60) # Wait a minute before retrying
    retry
  rescue Octokit::AbuseDetected => e
    Rails.logger.warn "[GithubChecksAPI] Abuse detection triggered for PR ##{pr_number}. Waiting 5 minutes..."
    sleep(300) # Wait 5 minutes as recommended
    retry
  rescue => e
    Rails.logger.error "[GithubChecksAPI] Error fetching checks for PR ##{pr_number}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    nil
  end
  
  def update_pr_with_checks(pr_number)
    pr = PullRequest.find_by(number: pr_number)
    unless pr
      Rails.logger.error "[GithubChecksAPI] PR ##{pr_number} not found in database"
      return false
    end
    
    check_data = fetch_pr_checks(pr_number)
    unless check_data
      Rails.logger.error "[GithubChecksAPI] Failed to fetch check data for PR ##{pr_number}"
      return false
    end
    
    # Update PR with check data
    pr.update!(
      ci_status: check_data[:overall_status],
      total_checks: check_data[:total_checks],
      successful_checks: check_data[:successful_checks],
      failed_checks: check_data[:failed_checks]
    )
    
    # Store failing checks in cache
    if check_data[:failing_checks].any?
      Rails.cache.write("pr_#{pr.id}_failing_checks", check_data[:failing_checks], expires_in: 1.hour)
    end
    
    # Store detailed check data in cache for frontend
    Rails.cache.write("pr_#{pr.id}_check_details", {
      pending: check_data[:pending_checks],
      skipped: check_data[:skipped_checks],
      failing_checks: check_data[:failing_checks]
    }, expires_in: 1.hour)
    
    # Update ready for backend review status
    pr.update_ready_for_backend_review!
    
    # Update approval status (sets approved_at if all checks passing)
    pr.update_approval_status!
    
    Rails.logger.info "[GithubChecksAPI] Successfully updated PR ##{pr_number}"
    true
  end
  
  def update_all_prs_with_checks
    updated_count = 0
    error_count = 0
    
    # Check rate limit before starting
    begin
      rate_limit = @client.rate_limit
      if rate_limit.remaining < 100
        wait_time = (rate_limit.resets_at - Time.now).to_i
        Rails.logger.warn "[GithubChecksAPI] Rate limit low (#{rate_limit.remaining} remaining). Waiting #{wait_time} seconds..."
        sleep(wait_time + 10) if wait_time > 0
      end
    rescue => e
      Rails.logger.warn "[GithubChecksAPI] Could not check rate limit: #{e.message}"
    end
    
    PullRequest.where(state: 'open').find_each.with_index do |pr, index|
      # Add longer delay every 10 PRs to avoid abuse detection
      if index > 0 && index % 10 == 0
        Rails.logger.info "[GithubChecksAPI] Pausing for 30 seconds after #{index} PRs to avoid rate limits..."
        sleep(30)
      end
      
      if update_pr_with_checks(pr.number)
        updated_count += 1
      else
        error_count += 1
      end
      
      # Rate limit awareness - GitHub allows 5000 requests per hour
      # Increase delay to avoid abuse detection
      sleep(2) # 2 second delay between PRs to avoid rate limits
    end
    
    Rails.logger.info "[GithubChecksAPI] Updated #{updated_count} PRs, #{error_count} errors"
    { updated: updated_count, errors: error_count }
  end
end
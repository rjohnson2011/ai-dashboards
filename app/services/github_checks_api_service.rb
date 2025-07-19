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
    
    Rails.logger.info "[GithubChecksAPI] Successfully updated PR ##{pr_number}"
    true
  end
  
  def update_all_prs_with_checks
    updated_count = 0
    error_count = 0
    
    PullRequest.where(state: 'open').find_each do |pr|
      if update_pr_with_checks(pr.number)
        updated_count += 1
      else
        error_count += 1
      end
      
      # Rate limit awareness - GitHub allows 5000 requests per hour
      sleep(0.5) # Small delay to avoid hitting rate limits
    end
    
    Rails.logger.info "[GithubChecksAPI] Updated #{updated_count} PRs, #{error_count} errors"
    { updated: updated_count, errors: error_count }
  end
end
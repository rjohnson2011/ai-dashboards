# Hybrid approach: Use GitHub API for data, scraping for missing pieces
class HybridPrCheckerService
  def initialize
    @github_service = GithubService.new
    @logger = Logger.new(STDOUT)
  end
  
  def get_accurate_pr_checks(pr)
    @logger.info "Getting accurate checks for PR ##{pr.number}"
    
    # Step 1: Get check runs from API (most accurate for GitHub Actions)
    check_runs = get_check_runs_from_api(pr)
    
    # Step 2: Get commit statuses (for Jenkins, CircleCI, etc.)
    commit_statuses = get_commit_statuses_from_api(pr)
    
    # Step 3: Combine and deduplicate
    all_checks = combine_checks(check_runs, commit_statuses)
    
    # Step 4: Get required checks from branch protection
    required_checks = get_required_checks(pr)
    
    # Step 5: Calculate summary
    result = {
      checks: all_checks,
      total_checks: all_checks.length,
      successful_checks: all_checks.count { |c| c[:status] == 'success' },
      failed_checks: all_checks.count { |c| c[:status] == 'failure' },
      pending_checks: all_checks.count { |c| c[:status] == 'pending' },
      overall_status: calculate_overall_status(all_checks)
    }
    
    @logger.info "Found #{result[:total_checks]} total checks (#{result[:successful_checks]} success, #{result[:failed_checks]} failed)"
    
    result
  end
  
  private
  
  def get_check_runs_from_api(pr)
    return [] unless pr.head_sha
    
    checks = []
    client = @github_service.instance_variable_get(:@client)
    owner = @github_service.instance_variable_get(:@owner)
    repo = @github_service.instance_variable_get(:@repo)
    
    begin
      # Get check runs
      response = client.check_runs_for_ref("#{owner}/#{repo}", pr.head_sha)
      
      response.check_runs.each do |run|
        status = case run.status
        when 'completed'
          case run.conclusion
          when 'success' then 'success'
          when 'failure', 'cancelled', 'timed_out' then 'failure'
          when 'neutral', 'skipped' then 'neutral'
          else 'unknown'
          end
        when 'in_progress', 'queued' then 'pending'
        else 'unknown'
        end
        
        checks << {
          name: run.name,
          status: status,
          suite_name: run.check_suite&.app&.name || 'GitHub Actions',
          url: run.html_url,
          required: false # Will be updated later
        }
      end
    rescue => e
      @logger.error "Error fetching check runs: #{e.message}"
    end
    
    checks
  end
  
  def get_commit_statuses_from_api(pr)
    return [] unless pr.head_sha
    
    statuses = []
    client = @github_service.instance_variable_get(:@client)
    owner = @github_service.instance_variable_get(:@owner)
    repo = @github_service.instance_variable_get(:@repo)
    
    begin
      # Get commit statuses (legacy API)
      response = client.statuses("#{owner}/#{repo}", pr.head_sha)
      
      # Group by context and take the latest
      grouped = response.group_by(&:context)
      
      grouped.each do |context, status_list|
        latest = status_list.max_by { |s| s.created_at }
        
        status = case latest.state
        when 'success' then 'success'
        when 'failure', 'error' then 'failure'
        when 'pending' then 'pending'
        else 'unknown'
        end
        
        statuses << {
          name: context,
          status: status,
          suite_name: 'Status Checks',
          url: latest.target_url,
          required: false
        }
      end
    rescue => e
      @logger.error "Error fetching commit statuses: #{e.message}"
    end
    
    statuses
  end
  
  def combine_checks(check_runs, commit_statuses)
    # Combine both sources
    all_checks = check_runs + commit_statuses
    
    # Remove duplicates based on name
    all_checks.uniq { |check| check[:name] }
  end
  
  def get_required_checks(pr)
    # TODO: Implement branch protection API call to get required checks
    # For now, return empty array
    []
  end
  
  def calculate_overall_status(checks)
    return 'unknown' if checks.empty?
    
    if checks.any? { |c| c[:status] == 'failure' }
      'failure'
    elsif checks.any? { |c| c[:status] == 'pending' }
      'pending'
    elsif checks.all? { |c| c[:status] == 'success' }
      'success'
    else
      'unknown'
    end
  end
end
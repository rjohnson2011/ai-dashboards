pr_number = 23158
github_service = GithubService.new

# Find the PR
pr = github_service.all_pull_requests(state: 'open').find { |p| p.number == pr_number }
if pr
  pr_record = PullRequest.find_by(number: pr_number)
  
  # Add the commit statuses
  combined_status = github_service.commit_status(pr.head.sha)
  if combined_status
    unique_statuses = combined_status.statuses.uniq { |s| s.context }
    
    unique_statuses.each do |status|
      mapped_status = case status.state
                      when 'success' then 'success'
                      when 'failure', 'error' then 'failure'
                      when 'pending' then 'pending'
                      else 'unknown'
                      end
      
      unless pr_record.check_runs.exists?(name: status.context)
        pr_record.check_runs.create!(
          name: status.context,
          status: mapped_status,
          url: status.target_url,
          description: status.description,
          required: false,
          suite_name: nil
        )
        puts "Added commit status: #{status.context} - #{mapped_status}"
      end
    end
  end
  
  # Update counts
  total = pr_record.check_runs.count
  successful = pr_record.check_runs.where(status: 'success').count
  failed = pr_record.check_runs.where(status: ['failure', 'error', 'cancelled']).count
  
  pr_record.update!(
    total_checks: total,
    successful_checks: successful,
    failed_checks: failed
  )
  
  puts "\nUpdated PR ##{pr_number}: #{failed} failing, #{successful} successful (#{total} total)"
  
  # List missing checks
  puts "\nCurrent checks in DB:"
  pr_record.check_runs.each do |check|
    puts "  #{check.name}: #{check.status}"
  end
end
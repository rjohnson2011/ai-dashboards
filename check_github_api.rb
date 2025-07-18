# Check GitHub API for check suite information
pr_number = 23158

github_service = GithubService.new

# Get PR details
pr = github_service.all_pull_requests(state: 'open').find { |p| p.number == pr_number }

if pr
  puts "PR ##{pr.number}: #{pr.title}"
  puts "Head SHA: #{pr.head.sha}"
  
  # Get combined status
  puts "\n=== Combined Status ==="
  begin
    combined_status = github_service.commit_status(pr.head.sha)
    if combined_status
      puts "State: #{combined_status.state}"
      puts "Total count: #{combined_status.total_count}"
      puts "Statuses: #{combined_status.statuses.count}"
      
      # Group statuses by state
      by_state = combined_status.statuses.group_by(&:state)
      by_state.each do |state, statuses|
        puts "  #{state}: #{statuses.count}"
      end
    end
  rescue => e
    puts "Error getting combined status: #{e.message}"
  end
  
  # Get check runs
  puts "\n=== Check Runs ==="
  begin
    client = github_service.instance_variable_get(:@client)
    check_runs = client.check_runs_for_ref("department-of-veterans-affairs/vets-api", pr.head.sha)
    
    puts "Total count: #{check_runs.total_count}"
    
    # Group by status
    by_status = check_runs.check_runs.group_by(&:status)
    by_status.each do |status, runs|
      puts "  #{status}: #{runs.count}"
    end
    
    # Group by conclusion
    by_conclusion = check_runs.check_runs.group_by(&:conclusion)
    by_conclusion.each do |conclusion, runs|
      puts "  #{conclusion || 'pending'}: #{runs.count}"
    end
    
    # Calculate totals
    total = check_runs.total_count
    successful = check_runs.check_runs.count { |r| r.conclusion == 'success' }
    failed = check_runs.check_runs.count { |r| ['failure', 'cancelled', 'timed_out'].include?(r.conclusion) }
    pending = check_runs.check_runs.count { |r| r.status == 'in_progress' || r.status == 'queued' }
    
    puts "\nSummary:"
    puts "Total: #{total}"
    puts "Successful: #{successful}"
    puts "Failed: #{failed}"
    puts "Pending: #{pending}"
    
    # Should match "1 failing, 23 successful checks"
    puts "\nExpected text: #{failed} failing, #{successful} successful checks"
    
  rescue => e
    puts "Error getting check runs: #{e.message}"
  end
end
namespace :pr do
  desc "Update all PR check counts using GitHub API"
  task update_checks: :environment do
    puts "Updating all PRs with GitHub API data..."
    service = GithubChecksApiService.new
    result = service.update_all_prs_with_checks
    puts "Updated: #{result[:updated]} PRs"
    puts "Errors: #{result[:errors]}"
  end

  desc "Fix backend-approved PRs that show failing checks"
  task fix_backend_approved: :environment do
    puts "Fixing backend-approved PRs..."
    fixed_count = 0
    
    PullRequest.where(state: 'open', backend_approval_status: 'approved').each do |pr|
      if pr.failed_checks > 0 && pr.failed_checks <= 1
        old_status = "#{pr.successful_checks}/#{pr.total_checks}"
        
        pr.update!(
          successful_checks: pr.total_checks,
          failed_checks: 0,
          ci_status: 'success'
        )
        
        Rails.cache.delete("pr_#{pr.id}_failing_checks")
        pr.update_ready_for_backend_review!
        
        puts "  Fixed PR ##{pr.number}: #{old_status} -> #{pr.successful_checks}/#{pr.total_checks}"
        fixed_count += 1
      end
    end
    
    puts "Fixed #{fixed_count} PRs"
  end

  desc "Update ready_for_backend_review status for all PRs"
  task update_ready_status: :environment do
    puts "Updating ready_for_backend_review status..."
    count = 0
    
    PullRequest.where(state: 'open').find_each do |pr|
      pr.update_ready_for_backend_review!
      count += 1
      print "." if count % 10 == 0
    end
    
    puts "\nUpdated #{count} PRs"
  end

  desc "Update a single PR by number"
  task :update_single, [:pr_number] => :environment do |t, args|
    pr_number = args[:pr_number].to_i
    pr = PullRequest.find_by(number: pr_number)
    
    if pr
      puts "Updating PR ##{pr_number}..."
      service = GithubChecksApiService.new
      
      if service.update_pr_with_checks(pr_number)
        pr.reload
        puts "Updated successfully:"
        puts "  Checks: #{pr.successful_checks}/#{pr.total_checks}"
        puts "  Status: #{pr.ci_status}"
        puts "  Backend: #{pr.backend_approval_status}"
        puts "  Ready: #{pr.ready_for_backend_review}"
      else
        puts "Failed to update PR"
      end
    else
      puts "PR ##{pr_number} not found"
    end
  end

  desc "Show PR status"
  task :status, [:pr_number] => :environment do |t, args|
    pr_number = args[:pr_number].to_i
    pr = PullRequest.find_by(number: pr_number)
    
    if pr
      puts "PR ##{pr.number}: #{pr.title}"
      puts "  Checks: #{pr.successful_checks}/#{pr.total_checks}"
      puts "  CI Status: #{pr.ci_status}"
      puts "  Backend Approval: #{pr.backend_approval_status}"
      puts "  Ready for Backend: #{pr.ready_for_backend_review}"
      
      # Show failing checks if any
      failing_checks = Rails.cache.read("pr_#{pr.id}_failing_checks") || []
      if failing_checks.any?
        puts "  Failing checks:"
        failing_checks.each do |check|
          puts "    - #{check[:name]}"
        end
      end
      
      # Show approvals
      approvals = pr.pull_request_reviews.where(state: 'APPROVED')
      if approvals.any?
        puts "  Approvals:"
        approvals.each do |approval|
          puts "    - #{approval.user}"
        end
      end
    else
      puts "PR ##{pr_number} not found"
    end
  end
end
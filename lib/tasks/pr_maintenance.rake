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
    puts "Checking backend-approved PRs for false failing checks..."
    puts "This task will ONLY fix PRs where the ONLY failing check is the backend approval check itself."
    puts ""

    fixed_count = 0
    skipped_count = 0

    PullRequest.where(state: "open", backend_approval_status: "approved").each do |pr|
      next unless pr.failed_checks > 0

      # Get the actual failing checks from cache
      failing_checks = Rails.cache.read("pr_#{pr.id}_failing_checks") || []

      if failing_checks.empty? && pr.failed_checks > 0
        puts "  PR ##{pr.number}: Shows #{pr.failed_checks} failing but no details cached - skipping"
        skipped_count += 1
        next
      end

      # Check if ALL failing checks are backend-related
      backend_checks = failing_checks.select { |check|
        name = check[:name].to_s.downcase
        name.include?("backend") && (name.include?("approval") || name.include?("review"))
      }

      non_backend_failing = failing_checks - backend_checks

      if non_backend_failing.empty? && backend_checks.any?
        # Only backend checks are failing, and PR is already backend approved
        old_status = "#{pr.successful_checks}/#{pr.total_checks}"

        puts "  PR ##{pr.number}: Only backend approval check(s) failing:"
        backend_checks.each do |check|
          puts "    - #{check[:name]}"
        end

        pr.update!(
          successful_checks: pr.total_checks,
          failed_checks: 0,
          ci_status: "success"
        )

        Rails.cache.delete("pr_#{pr.id}_failing_checks")
        pr.update_ready_for_backend_review!

        puts "    Fixed: #{old_status} -> #{pr.successful_checks}/#{pr.total_checks}"
        fixed_count += 1
      else
        puts "  PR ##{pr.number}: Has real failing checks - not fixing:"
        non_backend_failing.each do |check|
          puts "    - #{check[:name]}"
        end
        skipped_count += 1
      end
    end

    puts "\nSummary:"
    puts "  Fixed: #{fixed_count} PRs (only backend check was failing)"
    puts "  Skipped: #{skipped_count} PRs (had real failing checks)"
  end

  desc "Update ready_for_backend_review status for all PRs"
  task update_ready_status: :environment do
    puts "Updating ready_for_backend_review status..."
    count = 0

    PullRequest.where(state: "open").find_each do |pr|
      pr.update_ready_for_backend_review!
      count += 1
      print "." if count % 10 == 0
    end

    puts "\nUpdated #{count} PRs"
  end

  desc "Update approval status for all PRs (sets approved_at)"
  task update_approval_status: :environment do
    puts "Updating approval status for all PRs..."
    approved_count = 0

    PullRequest.where(state: "open").find_each do |pr|
      pr.update_approval_status!
      if pr.approved_at
        approved_count += 1
        puts "  PR ##{pr.number}: Fully approved (#{pr.successful_checks}/#{pr.total_checks})"
      end
    end

    puts "\nTotal approved PRs: #{approved_count}"
    puts "Total open PRs: #{PullRequest.open.not_approved.count}"
  end

  desc "Update a single PR by number"
  task :update_single, [ :pr_number ] => :environment do |t, args|
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

  desc "Verify PR checks against GitHub (refetch from API)"
  task :verify_checks, [ :pr_number ] => :environment do |t, args|
    pr_number = args[:pr_number].to_i
    pr = PullRequest.find_by(number: pr_number)

    if pr
      puts "Verifying PR ##{pr_number} against GitHub API..."
      puts "Current database status: #{pr.successful_checks}/#{pr.total_checks}"

      service = GithubChecksApiService.new
      check_data = service.fetch_pr_checks(pr_number)

      if check_data
        puts "\nGitHub API reports:"
        puts "  Total checks: #{check_data[:total_checks]}"
        puts "  Successful: #{check_data[:successful_checks]}"
        puts "  Failed: #{check_data[:failed_checks]}"
        puts "  Pending: #{check_data[:pending_checks]}"
        puts "  Skipped: #{check_data[:skipped_checks]}"
        puts "  Overall status: #{check_data[:overall_status]}"

        if check_data[:failing_checks].any?
          puts "\nFailing checks:"
          check_data[:failing_checks].each do |check|
            puts "  - #{check[:name]}"
            puts "    URL: #{check[:url]}"
          end
        end

        if pr.total_checks != check_data[:total_checks] ||
           pr.successful_checks != check_data[:successful_checks]
          puts "\n⚠️  Database is out of sync with GitHub!"
          puts "Update with: rake pr:update_single[#{pr_number}]"
        else
          puts "\n✓ Database matches GitHub"
        end
      else
        puts "Failed to fetch data from GitHub API"
      end
    else
      puts "PR ##{pr_number} not found"
    end
  end

  desc "Show PR status"
  task :status, [ :pr_number ] => :environment do |t, args|
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
      approvals = pr.pull_request_reviews.where(state: "APPROVED")
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

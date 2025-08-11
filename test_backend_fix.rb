#!/usr/bin/env ruby
# Test script to verify backend approval fixes

pr = PullRequest.find_by(number: 23380)
if pr
  puts "Testing PR #23380 (backend approved: #{pr.backend_approval_status})"
  checker = HybridPrCheckerService.new
  result = checker.get_accurate_pr_checks(pr)

  puts "\nCheck status after fix:"
  puts "Overall CI status: #{result[:overall_status]}"
  puts "Failed checks: #{result[:failed_checks]}"

  # Check specific checks
  result[:checks].each do |check|
    if check[:name].include?('Pull Request Ready for Review') || check[:name].include?('backend approval')
      puts "  #{check[:name]}: #{check[:status]}"
    end
  end

  # Update the PR
  pr.update!(
    ci_status: result[:overall_status],
    total_checks: result[:total_checks],
    successful_checks: result[:successful_checks],
    failed_checks: result[:failed_checks]
  )

  puts "\nPR updated - new CI status: #{pr.ci_status}"
end

# Test the ready_for_backend_review logic
require_relative 'config/environment'

# Test a few PRs
test_prs = [23165, 23012, 23132]

test_prs.each do |pr_number|
  pr = PullRequest.find_by(number: pr_number)
  next unless pr
  
  puts "\nPR ##{pr_number}: #{pr.title[0..50]}..."
  puts "  CI Status: #{pr.ci_status}"
  puts "  Total Checks: #{pr.total_checks}"
  puts "  Failed Checks: #{pr.failed_checks}"
  puts "  Backend Approval: #{pr.backend_approval_status}"
  
  # Check failing checks details
  failing_checks = Rails.cache.read("pr_#{pr.id}_failing_checks") || []
  if failing_checks.any?
    puts "  Failing checks:"
    failing_checks.each do |check|
      puts "    - #{check[:name]}"
    end
  end
  
  # Check approvals
  reviews = pr.pull_request_reviews.where(state: 'APPROVED')
  backend_members = BackendReviewGroupMember.pluck(:username)
  
  puts "  Approvals:"
  reviews.each do |review|
    is_backend = backend_members.include?(review.user)
    puts "    - #{review.user}#{is_backend ? ' (backend)' : ''}"
  end
  
  # Calculate ready for backend review
  pr.update_ready_for_backend_review!
  puts "  Ready for Backend Review: #{pr.ready_for_backend_review ? '✓' : '✗'}"
end
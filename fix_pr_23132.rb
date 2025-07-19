pr = PullRequest.find_by(number: 23132)
pr.update!(
  total_checks: 24,
  successful_checks: 23,
  failed_checks: 0,
  ci_status: 'pending'  # Since there's 1 pending check
)
puts "Updated PR #23132:"
puts "  Total: #{pr.total_checks}"
puts "  Success: #{pr.successful_checks}"
puts "  Failed: #{pr.failed_checks}"
puts "  CI Status: #{pr.ci_status}"
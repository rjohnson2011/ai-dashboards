pr = PullRequest.find_by(number: 23012)
pr.update!(
  total_checks: 24,
  successful_checks: 23,
  failed_checks: 1,
  ci_status: 'failure'
)
puts "Updated PR #23012:"
puts "  Total: #{pr.total_checks}"
puts "  Success: #{pr.successful_checks}"
puts "  Failed: #{pr.failed_checks}"
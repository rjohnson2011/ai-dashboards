#!/usr/bin/env ruby

pr_number = ARGV[0]&.to_i || 23179
pr = PullRequest.find_by(number: pr_number)

if pr.nil?
  puts "PR ##{pr_number} not found"
  exit 1
end

puts "Updating CI status for PR ##{pr.number}: #{pr.title}"
puts "\nBefore update:"
puts "  ci_status: '#{pr.ci_status}'"
puts "  total_checks: #{pr.total_checks}"
puts "  backend_approval_status: '#{pr.backend_approval_status}'"

# Run hybrid checker to update CI status
hybrid_service = HybridPrCheckerService.new
result = hybrid_service.get_accurate_pr_checks(pr)

pr.update!(
  ci_status: result[:overall_status],
  total_checks: result[:total_checks],
  successful_checks: result[:successful_checks],
  failed_checks: result[:failed_checks],
  pending_checks: result[:pending_checks] || 0
)

# Also update check runs
pr.check_runs.destroy_all
result[:checks].each do |check|
  pr.check_runs.create!(
    name: check[:name],
    status: check[:status] || 'unknown',
    url: check[:url],
    description: check[:description],
    required: check[:required] || false,
    suite_name: check[:suite_name]
  )
end

puts "\nAfter update:"
puts "  ci_status: '#{pr.ci_status}'"
puts "  total_checks: #{pr.total_checks}"
puts "  successful_checks: #{pr.successful_checks}"
puts "  failed_checks: #{pr.failed_checks}"
puts "  pending_checks: #{pr.pending_checks}"
puts "  backend_approval_status: '#{pr.backend_approval_status}'"

# Check the approval summary
puts "\nApproval summary:"
puts pr.approval_summary.inspect
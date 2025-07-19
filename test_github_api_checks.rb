# Test the GitHub API service on problematic PRs
require_relative 'config/environment'

service = GithubChecksApiService.new

# Test PR #23012 (should show 23/24)
puts "Testing PR #23012..."
result = service.fetch_pr_checks(23012)
if result
  puts "  Total checks: #{result[:total_checks]}"
  puts "  Successful: #{result[:successful_checks]}"
  puts "  Failed: #{result[:failed_checks]}"
  puts "  Pending: #{result[:pending_checks]}"
  puts "  Skipped: #{result[:skipped_checks]}"
  puts "  Status: #{result[:overall_status]}"
  
  if result[:failing_checks].any?
    puts "  Failing checks:"
    result[:failing_checks].each do |check|
      puts "    - #{check[:name]}: #{check[:description]}"
    end
  end
end

puts "\nTesting PR #23132..."
result = service.fetch_pr_checks(23132)
if result
  puts "  Total checks: #{result[:total_checks]}"
  puts "  Successful: #{result[:successful_checks]}"
  puts "  Failed: #{result[:failed_checks]}"
  puts "  Pending: #{result[:pending_checks]}"
  puts "  Skipped: #{result[:skipped_checks]}"
  puts "  Status: #{result[:overall_status]}"
end

# Update PRs with the API data
puts "\nUpdating PRs with API data..."
service.update_pr_with_checks(23012)
service.update_pr_with_checks(23132)

# Check database values
pr1 = PullRequest.find_by(number: 23012)
pr2 = PullRequest.find_by(number: 23132)

puts "\nDatabase values after update:"
puts "PR #23012: #{pr1.successful_checks}/#{pr1.total_checks} (#{pr1.ci_status})"
puts "PR #23132: #{pr2.successful_checks}/#{pr2.total_checks} (#{pr2.ci_status})"
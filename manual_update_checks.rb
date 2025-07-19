# Manual script to update PR checks using GitHub API
require_relative 'config/environment'

puts "Starting manual update of PR checks..."

# Update all open PRs with GitHub API data
service = GithubChecksApiService.new
result = service.update_all_prs_with_checks

puts "\nUpdate complete!"
puts "Updated: #{result[:updated]} PRs"
puts "Errors: #{result[:errors]}"

# Check a few specific PRs
[23165, 23012, 23132].each do |pr_number|
  pr = PullRequest.find_by(number: pr_number)
  if pr
    puts "\nPR ##{pr_number}:"
    puts "  Checks: #{pr.successful_checks}/#{pr.total_checks}"
    puts "  Status: #{pr.ci_status}"
    puts "  Backend approval: #{pr.backend_approval_status}"
  end
end

# Force cache clear
Rails.cache.clear
puts "\nCache cleared."
pr = PullRequest.find_by(number: 23142)
puts "PR ##{pr.number} - State in DB: #{pr.state}"

# Check GitHub for actual status
github_token = ENV['GITHUB_TOKEN']
owner = ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs'
repo = ENV['GITHUB_REPO'] || 'vets-api'
client = Octokit::Client.new(access_token: github_token)

github_pr = client.pull_request("#{owner}/#{repo}", pr.number)
puts "PR ##{pr.number} - State on GitHub: #{github_pr.state}"
puts "Merged: #{github_pr.merged}"
puts "Merged at: #{github_pr.merged_at}"

# Update if different
if github_pr.state != pr.state || github_pr.merged
  pr.update!(state: github_pr.merged ? 'merged' : github_pr.state)
  puts "Updated PR state to: #{pr.state}"
end

# Check how many PRs we have that might be stale
stale_count = PullRequest.where(state: 'open').where('pr_updated_at < ?', 1.day.ago).count
puts "\nFound #{stale_count} PRs that haven't been updated in over a day"
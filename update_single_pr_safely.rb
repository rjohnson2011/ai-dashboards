# Update a single PR with rate limit handling
require_relative 'config/environment'

pr_number = ARGV[0]&.to_i || 23165

puts "Updating PR ##{pr_number} with rate limit handling..."

service = GithubChecksApiService.new

# Check current rate limit
begin
  client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
  rate_limit = client.rate_limit
  
  puts "\nCurrent rate limit status:"
  puts "  Remaining: #{rate_limit.remaining}/#{rate_limit.limit}"
  puts "  Resets at: #{rate_limit.resets_at} (#{(rate_limit.resets_at - Time.now).to_i} seconds)"
  
  if rate_limit.remaining < 10
    wait_time = (rate_limit.resets_at - Time.now).to_i + 10
    puts "\nRate limit is too low. Waiting #{wait_time} seconds..."
    sleep(wait_time)
  end
rescue => e
  puts "Could not check rate limit: #{e.message}"
end

# Update the single PR
success = service.update_pr_with_checks(pr_number)

if success
  pr = PullRequest.find_by(number: pr_number)
  puts "\nSuccessfully updated PR ##{pr_number}:"
  puts "  Total checks: #{pr.total_checks}"
  puts "  Successful: #{pr.successful_checks}"
  puts "  Failed: #{pr.failed_checks}"
  puts "  CI Status: #{pr.ci_status}"
else
  puts "\nFailed to update PR ##{pr_number}"
end

# Check rate limit after
begin
  rate_limit = client.rate_limit
  puts "\nRate limit after update:"
  puts "  Remaining: #{rate_limit.remaining}/#{rate_limit.limit}"
rescue => e
  puts "Could not check rate limit: #{e.message}"
end
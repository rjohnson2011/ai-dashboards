#!/usr/bin/env ruby

pr = PullRequest.find_by(number: 23179)
if pr.nil?
  puts 'PR #23179 not found, creating...'
  # Fetch from API
  github_service = GithubService.new
  client = github_service.instance_variable_get(:@client)
  owner = github_service.instance_variable_get(:@owner)
  repo = github_service.instance_variable_get(:@repo)
  
  api_pr = client.pull_request("#{owner}/#{repo}", 23179)
  pr = PullRequest.create!(
    number: 23179,
    github_id: api_pr.id,
    title: api_pr.title,
    author: api_pr.user.login,
    state: api_pr.state,
    url: api_pr.html_url,
    pr_created_at: api_pr.created_at,
    pr_updated_at: api_pr.updated_at,
    head_sha: api_pr.head.sha
  )
end

puts "PR #23179: #{pr.title}"
puts "Author: #{pr.author}"
puts "Current backend approval status: #{pr.backend_approval_status}"
puts "Approved at: #{pr.approved_at}"

# Check reviews
puts "\nFetching reviews from API..."
github_service = GithubService.new
reviews = github_service.pull_request_reviews(pr.number)

puts "Found #{reviews.count} reviews:"
reviews.each do |review|
  puts "  - #{review.user.login}: #{review.state} at #{review.submitted_at}"
  
  # Save review to database
  PullRequestReview.find_or_create_by(
    pull_request_id: pr.id,
    github_id: review.id
  ).update!(
    user: review.user.login,
    state: review.state,
    submitted_at: review.submitted_at
  )
end

# Check backend reviewers
puts "\nChecking backend reviewers..."
backend_reviewers = %w[
  rmtolmach jefflembeck Gauravjo klawson88 bkjohnson jmtaber129 
  stevenshoen coope93 bosawt penley LindseySaari cjhubbs
]

approved_by_backend = reviews.any? do |review|
  review.state == 'APPROVED' && backend_reviewers.include?(review.user.login)
end

puts "Backend reviewers who reviewed:"
reviews.each do |review|
  if backend_reviewers.include?(review.user.login)
    puts "  - #{review.user.login}: #{review.state}"
  end
end

puts "\nApproved by backend reviewer? #{approved_by_backend}"

# Update backend approval status
puts "\nUpdating backend approval status..."
pr.update_backend_approval_status!
pr.reload

puts "New backend approval status: #{pr.backend_approval_status}"
puts "Approved at: #{pr.approved_at}"

# Check the actual checks
puts "\nChecking CI status..."
hybrid_service = HybridPrCheckerService.new
result = hybrid_service.get_accurate_pr_checks(pr)

puts "CI Status: #{result[:overall_status]}"
puts "Total checks: #{result[:total_checks]} (#{result[:successful_checks]} success, #{result[:failed_checks]} failed)"

# Check for backend approval check
backend_check = result[:checks].find { |c| c[:name].include?('backend approval') }
if backend_check
  puts "\nBackend approval check: #{backend_check[:status]}"
else
  puts "\nNo backend approval check found in CI"
end
#!/usr/bin/env ruby
# Update PR reviews and backend approval status

pr_number = ARGV[0]&.to_i
if pr_number.nil? || pr_number == 0
  puts "Usage: rails runner scripts/update_pr_reviews.rb PR_NUMBER"
  exit 1
end

pr = PullRequest.find_by(number: pr_number)
if pr.nil?
  puts "PR ##{pr_number} not found"
  exit 1
end

puts "Updating reviews for PR ##{pr.number}: #{pr.title}"

# Fetch reviews from GitHub
github_service = GithubService.new
reviews = github_service.pull_request_reviews(pr.number)

puts "Found #{reviews.count} reviews:"
reviews.each do |review_data|
  puts "  - #{review_data.user.login}: #{review_data.state} at #{review_data.submitted_at}"
  
  # Update or create review record
  PullRequestReview.find_or_create_by(
    pull_request_id: pr.id,
    github_id: review_data.id
  ).update!(
    user: review_data.user.login,
    state: review_data.state,
    submitted_at: review_data.submitted_at
  )
end

# Update backend approval status
old_status = pr.backend_approval_status
pr.update_backend_approval_status!
pr.update_ready_for_backend_review!
pr.update_approval_status!

puts "\nBackend approval status: #{old_status} -> #{pr.backend_approval_status}"

# Show which backend reviewer approved (if any)
if pr.backend_approval_status == 'approved'
  backend_members = BackendReviewGroupMember.pluck(:username)
  approvers = pr.pull_request_reviews
                .where(state: 'APPROVED')
                .where(user: backend_members)
                .pluck(:user)
  
  puts "Approved by backend reviewers: #{approvers.join(', ')}"
end
#!/usr/bin/env ruby
# Check and manage backend reviewers

puts 'Backend Review Group Members in database:'
BackendReviewGroupMember.pluck(:username).sort.each do |username|
  puts "  - #{username}"
end

# Check if a specific user is a backend reviewer
if ARGV[0]
  username = ARGV[0]
  is_member = BackendReviewGroupMember.exists?(username: username)
  puts "\nIs #{username} a backend reviewer? #{is_member}"
  
  if !is_member && ARGV[1] == 'add'
    puts "Adding #{username} to backend reviewers..."
    BackendReviewGroupMember.create!(username: username)
    puts "Added successfully!"
  end
end

# Show recent PR approvals by backend reviewers
puts "\nRecent backend approvals:"
PullRequest.where(backend_approval_status: 'approved')
           .order(updated_at: :desc)
           .limit(5)
           .each do |pr|
  reviews = pr.pull_request_reviews.where(state: 'APPROVED')
  backend_reviewers = reviews.joins("INNER JOIN backend_review_group_members ON pull_request_reviews.user = backend_review_group_members.username")
  
  if backend_reviewers.any?
    puts "  PR ##{pr.number}: approved by #{backend_reviewers.pluck(:user).join(', ')}"
  end
end
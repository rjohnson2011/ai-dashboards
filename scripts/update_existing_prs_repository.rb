#!/usr/bin/env ruby

# Update existing PRs to have repository_name and repository_owner set

PullRequest.where(repository_name: nil).update_all(
  repository_name: ENV['GITHUB_REPO'] || 'vets-api',
  repository_owner: ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs'
)

puts "Updated #{PullRequest.where(repository_name: ENV['GITHUB_REPO'] || 'vets-api').count} PRs with repository information"

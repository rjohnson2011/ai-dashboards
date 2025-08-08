#!/usr/bin/env ruby

# Update existing snapshots to have repository_name and repository_owner set
DailySnapshot.where(repository_name: nil).update_all(
  repository_name: ENV['GITHUB_REPO'] || 'vets-api',
  repository_owner: ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs'
)

puts "Updated #{DailySnapshot.where(repository_name: ENV['GITHUB_REPO'] || 'vets-api').count} snapshots with repository information"
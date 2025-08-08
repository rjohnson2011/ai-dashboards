#!/usr/bin/env ruby

puts "Populating data for non-vets-api repositories..."

RepositoryConfig.all.each do |repo|
  next if repo.name == 'vets-api' # Skip vets-api
  
  puts "\nStarting #{repo.full_name}..."
  
  # Queue the job instead of running synchronously
  FetchAllPullRequestsJob.perform_later(
    repository_name: repo.name,
    repository_owner: repo.owner
  )
  
  puts "Queued fetch job for #{repo.full_name}"
end

puts "\nAll fetch jobs queued. Data will populate in the background."
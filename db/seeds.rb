# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Set up repository configurations
repositories = [
  { owner: 'department-of-veterans-affairs', name: 'vets-api' },
  { owner: 'department-of-veterans-affairs', name: 'platform-atlas' },
  { owner: 'department-of-veterans-affairs', name: 'vets-json-schema' },
  { owner: 'department-of-veterans-affairs', name: 'vets-api-mockdata' }
]

puts "Setting up repository configurations..."
repositories.each do |repo|
  config = RepositoryConfig.find_or_create_by!(owner: repo[:owner], name: repo[:name])
  puts "  ✓ #{repo[:owner]}/#{repo[:name]}"
end

# Set up backend review group members
backend_members = [
  'ericboehs',
  'LindseySaari',
  'rmtolmach',
  'stiehlrod',
  'RachalCassity',
  'rjohnson2011',
  'stevenjcumming'
]

puts "\nSetting up backend review group members..."
backend_members.each do |username|
  member = BackendReviewGroupMember.find_or_create_by!(username: username)
  puts "  ✓ #{username}"
end

puts "\nSeed data created successfully!"

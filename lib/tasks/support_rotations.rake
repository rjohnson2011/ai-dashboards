namespace :support_rotations do
  desc "Seed initial support rotation data"
  task seed: :environment do
    puts "Creating support rotations..."

    # Current sprint (Sprint 104)
    SupportRotation.find_or_create_by!(
      sprint_number: 104,
      start_date: Date.new(2025, 11, 6),
      end_date: Date.new(2025, 11, 19)
    ) do |rotation|
      rotation.engineer_name = "rjohnson2011"
      rotation.repository_name = "vets-api"
      rotation.repository_owner = "department-of-veterans-affairs"
    end

    # Previous sprint (Sprint 103)
    SupportRotation.find_or_create_by!(
      sprint_number: 103,
      start_date: Date.new(2025, 10, 23),
      end_date: Date.new(2025, 11, 5)
    ) do |rotation|
      rotation.engineer_name = "RachalCassity"
      rotation.repository_name = "vets-api"
      rotation.repository_owner = "department-of-veterans-affairs"
    end

    # Sprint 102
    SupportRotation.find_or_create_by!(
      sprint_number: 102,
      start_date: Date.new(2025, 10, 9),
      end_date: Date.new(2025, 10, 22)
    ) do |rotation|
      rotation.engineer_name = "stiehlrod"
      rotation.repository_name = "vets-api"
      rotation.repository_owner = "department-of-veterans-affairs"
    end

    puts "Created #{SupportRotation.count} support rotations"
  end
end

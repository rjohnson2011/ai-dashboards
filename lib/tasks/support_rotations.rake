namespace :support_rotations do
  desc "Update future support rotations based on calendar"
  task update: :environment do
    repository_name = ENV["GITHUB_REPO"] || "vets-api"
    repository_owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"

    # Delete all future rotations (after current sprint)
    current_date = Date.today
    deleted_count = SupportRotation.where("start_date > ?", current_date).destroy_all.count

    puts "Deleted #{deleted_count} future rotations"
    puts "Creating new rotations..."

    rotations = [
      # December 2025 - January 2026
      { sprint_number: 16, engineer_name: "stevenjcumming", start_date: "2025-12-04", end_date: "2025-12-17" },
      { sprint_number: 17, engineer_name: "rmtolmach", start_date: "2025-12-18", end_date: "2025-12-31" },
      { sprint_number: 18, engineer_name: "stiehlrod", start_date: "2026-01-01", end_date: "2026-01-14" },
      { sprint_number: 19, engineer_name: "RachalCassity", start_date: "2026-01-15", end_date: "2026-01-28" },

      # February - March 2026
      { sprint_number: 20, engineer_name: "rjohnson2011", start_date: "2026-01-29", end_date: "2026-02-11" },
      { sprint_number: 21, engineer_name: "Crankums", start_date: "2026-02-12", end_date: "2026-02-25" },
      { sprint_number: 22, engineer_name: "stevenjcumming", start_date: "2026-02-26", end_date: "2026-03-11" },
      { sprint_number: 23, engineer_name: "jweissman", start_date: "2026-03-12", end_date: "2026-03-25" },

      # March - April 2026
      { sprint_number: 24, engineer_name: "rmtolmach", start_date: "2026-03-26", end_date: "2026-04-08" },
      { sprint_number: 25, engineer_name: "stiehlrod", start_date: "2026-04-09", end_date: "2026-04-22" },
      { sprint_number: 26, engineer_name: "RachalCassity", start_date: "2026-04-23", end_date: "2026-05-06" },

      # May - June 2026
      { sprint_number: 27, engineer_name: "rjohnson2011", start_date: "2026-05-07", end_date: "2026-05-20" },
      { sprint_number: 28, engineer_name: "Crankums", start_date: "2026-05-21", end_date: "2026-06-03" },
      { sprint_number: 29, engineer_name: "stevenjcumming", start_date: "2026-06-04", end_date: "2026-06-17" }
    ]

    rotations.each do |rotation_data|
      rotation = SupportRotation.create!(
        sprint_number: rotation_data[:sprint_number],
        engineer_name: rotation_data[:engineer_name],
        start_date: Date.parse(rotation_data[:start_date]),
        end_date: Date.parse(rotation_data[:end_date]),
        repository_name: repository_name,
        repository_owner: repository_owner
      )
      puts "Created Sprint ##{rotation.sprint_number}: #{rotation.engineer_name} (#{rotation.start_date} to #{rotation.end_date})"
    end

    puts "\nAll rotations updated successfully!"
  end
end

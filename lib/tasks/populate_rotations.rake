namespace :rotations do
  desc "Populate support rotation schedule"
  task populate: :environment do
    rotations = [
      { sprint_number: 15, engineer: 'rjohnson2011', start_date: '2025-11-20', end_date: '2025-12-03' },
      { sprint_number: 16, engineer: 'stevenjcumming', start_date: '2025-12-04', end_date: '2025-12-17' },
      { sprint_number: 17, engineer: 'ericboehs', start_date: '2025-12-18', end_date: '2025-12-31' },
      { sprint_number: 18, engineer: 'rmtolmach', start_date: '2026-01-01', end_date: '2026-01-14' },
      { sprint_number: 19, engineer: 'RachalCassity', start_date: '2026-01-15', end_date: '2026-01-28' },
      { sprint_number: 20, engineer: 'rjohnson2011', start_date: '2026-02-12', end_date: '2026-02-25' }
    ]

    rotations.each do |r|
      rotation = SupportRotation.find_or_initialize_by(sprint_number: r[:sprint_number])
      rotation.update!(
        engineer_name: r[:engineer],
        start_date: Date.parse(r[:start_date]),
        end_date: Date.parse(r[:end_date]),
        repository_name: 'vets-api',
        repository_owner: 'department-of-veterans-affairs'
      )
      puts "✓ Sprint #{r[:sprint_number]}: #{r[:engineer]} (#{r[:start_date]} to #{r[:end_date]})"
    end

    puts "\nDone! Added #{rotations.count} rotations."
  end
end

namespace :sprint do
  desc "Update current sprint data"
  task :update, [:sprint_number, :engineer, :start_date, :end_date] => :environment do |t, args|
    sprint_number = args[:sprint_number].to_i
    engineer = args[:engineer]
    start_date = Date.parse(args[:start_date])
    end_date = Date.parse(args[:end_date])
    
    puts "Updating sprint data..."
    puts "Sprint ##{sprint_number}: #{engineer} from #{start_date} to #{end_date}"

    # Delete old sprint data (both lower and higher sprint numbers)
    SupportRotation.where("sprint_number != ?", sprint_number).destroy_all
    
    # Create or update current sprint
    rotation = SupportRotation.find_or_initialize_by(sprint_number: sprint_number)
    rotation.update!(
      engineer_name: engineer,
      start_date: start_date,
      end_date: end_date,
      repository_name: 'vets-api',
      repository_owner: 'department-of-veterans-affairs'
    )
    
    puts "✓ Sprint #{sprint_number} updated successfully!"
  end
end

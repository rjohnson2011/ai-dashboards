PullRequest.find_by(number: 23142).update!(state: 'merged')
puts "PR 23142 marked as merged"
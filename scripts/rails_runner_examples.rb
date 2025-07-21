#!/usr/bin/env ruby
# Examples of correct rails runner usage

# CORRECT EXAMPLES:

# 1. Simple one-liners (no escaping needed)
# rails runner "puts User.count"
# rails runner "PullRequest.find(123).update!(status: 'approved')"

# 2. Multi-line with proper syntax
# rails runner "
#   pr = PullRequest.find(123)
#   pr.update!(status: 'approved')
#   puts pr.status
# "

# 3. Using script files (preferred for complex operations)
# rails runner scripts/update_pr_status.rb

# INCORRECT EXAMPLES TO AVOID:

# DON'T: rails runner "Model.create\!(name: 'test')"  # Unnecessary backslash
# DON'T: rails runner 'Model.where(name: "test")'     # Quote mixing issues
# DON'T: Use complex heredocs in command line

# GUIDELINES:

puts "Rails Runner Best Practices:"
puts "1. Use double quotes for the command string"
puts "2. Don't escape special characters like ! or # inside double quotes"
puts "3. For complex operations, create a script file"
puts "4. Test locally before running in production"

# Example: Safely checking PR status
def check_pr_status(pr_number)
  pr = PullRequest.find_by(number: pr_number)
  if pr
    puts "PR ##{pr.number}: #{pr.title}"
    puts "Status: #{pr.ci_status}"
    puts "Backend approval: #{pr.backend_approval_status}"
  else
    puts "PR ##{pr_number} not found"
  end
end

# Run if called directly
if __FILE__ == $0 && ARGV[0]
  check_pr_status(ARGV[0].to_i)
end
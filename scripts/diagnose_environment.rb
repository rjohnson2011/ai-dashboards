#!/usr/bin/env ruby
# Diagnostic script to understand Render environment

puts "=== DIAGNOSTIC INFORMATION ==="
puts "Ruby version: #{RUBY_VERSION}"
puts "Current directory: #{Dir.pwd}"
puts "Script location: #{__FILE__}"
puts

puts "=== DIRECTORY STRUCTURE ==="
puts "Contents of current directory:"
Dir.entries(".").sort.each { |f| puts "  #{f}" }
puts

if Dir.exist?("src")
  puts "WARNING: 'src' directory exists - this is OLD structure!"
  puts "Contents of src:"
  Dir.entries("src").sort.each { |f| puts "  src/#{f}" }
end

puts "\n=== CHECKING FOR AUTH CONTROLLER ==="
auth_paths = [
  "app/controllers/api/v1/auth_controller.rb",
  "src/app/controllers/api/v1/auth_controller.rb"
]

auth_paths.each do |path|
  if File.exist?(path)
    puts "FOUND: #{path}"
    puts "First few lines:"
    puts File.read(path).lines.first(5).join
  else
    puts "NOT FOUND: #{path}"
  end
end

puts "\n=== GIT INFORMATION ==="
if system("which git > /dev/null 2>&1")
  puts "Current commit:"
  system("git log -1 --oneline")
  puts "\nGit status:"
  system("git status --short")
  puts "\nRemote URL:"
  system("git remote -v | head -1")
else
  puts "Git not available"
end

puts "\n=== ENVIRONMENT VARIABLES ==="
puts "RAILS_ENV: #{ENV['RAILS_ENV']}"
puts "RENDER_SERVICE_NAME: #{ENV['RENDER_SERVICE_NAME']}"
puts "RENDER_INSTANCE_ID: #{ENV['RENDER_INSTANCE_ID']}"

puts "\n=== BUNDLE INFO ==="
if File.exist?("Gemfile.lock")
  puts "Gemfile.lock exists"
  rails_version = File.read("Gemfile.lock").match(/rails \((\d+\.\d+\.\d+)\)/)
  puts "Rails version from Gemfile.lock: #{rails_version[1]}" if rails_version
else
  puts "Gemfile.lock NOT FOUND"
end

puts "\n=== END DIAGNOSTIC ==="

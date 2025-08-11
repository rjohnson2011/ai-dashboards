#!/usr/bin/env ruby
# Script to test and fix database connection issues

puts "Testing Database Connection..."
puts "Rails Environment: #{ENV['RAILS_ENV']}"
puts "DATABASE_URL present: #{ENV['DATABASE_URL'].present?}"

if ENV['DATABASE_URL']
  puts "DATABASE_URL format: #{ENV['DATABASE_URL'].match?(/^postgres/) ? 'Valid PostgreSQL URL' : 'Invalid format'}"

  # Parse the URL
  require 'uri'
  uri = URI.parse(ENV['DATABASE_URL'])
  puts "\nParsed connection details:"
  puts "  Host: #{uri.host}"
  puts "  Port: #{uri.port}"
  puts "  Database: #{uri.path&.delete('/')}"
  puts "  User: #{uri.user}"
end

puts "\nTrying direct connection..."
begin
  require 'pg'

  if ENV['DATABASE_URL']
    uri = URI.parse(ENV['DATABASE_URL'])
    conn = PG.connect(
      host: uri.host,
      port: uri.port,
      dbname: uri.path&.delete('/'),
      user: uri.user,
      password: uri.password
    )

    result = conn.exec("SELECT version()")
    puts "✅ Direct connection successful!"
    puts "PostgreSQL version: #{result.first['version']}"
    conn.close
  end
rescue => e
  puts "❌ Direct connection failed: #{e.message}"
end

puts "\nChecking Rails database config..."
require_relative '../config/environment'

config = ActiveRecord::Base.connection_config
puts "Rails is using:"
puts "  adapter: #{config[:adapter]}"
puts "  host: #{config[:host]}"
puts "  database: #{config[:database]}"
puts "  port: #{config[:port]}"

# Try to establish connection with explicit config
puts "\nTrying Rails connection with explicit URL..."
begin
  ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])
  ActiveRecord::Base.connection.execute("SELECT 1")
  puts "✅ Rails connection successful!"

  # Now try to run pending migrations
  pending = ActiveRecord::Base.connection.migration_context.needs_migration?
  if pending
    puts "\nPending migrations found. Running..."
    ActiveRecord::Base.connection.migration_context.migrate
    puts "✅ Migrations completed!"
  else
    puts "\nNo pending migrations."
  end
rescue => e
  puts "❌ Rails connection failed: #{e.message}"
  puts e.backtrace.first(5)
end

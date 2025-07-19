#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'uri'

# Configuration
BASE_URL = ENV['API_URL'] || 'https://ai-dashboards.onrender.com'
ADMIN_TOKEN = ENV['ADMIN_TOKEN']

if ADMIN_TOKEN.nil? || ADMIN_TOKEN.empty?
  puts "❌ Error: ADMIN_TOKEN environment variable not set"
  puts "   Run: export ADMIN_TOKEN=your_admin_token"
  exit 1
end

puts "🔍 Verifying Webhook Setup"
puts "=" * 50
puts "API URL: #{BASE_URL}"
puts

# Step 1: Check if API is up
begin
  uri = URI("#{BASE_URL}/up")
  response = Net::HTTP.get_response(uri)
  if response.code == '200'
    puts "✅ API is up and running"
  else
    puts "❌ API health check failed: #{response.code}"
    exit 1
  end
rescue => e
  puts "❌ Cannot connect to API: #{e.message}"
  exit 1
end

# Step 2: Check webhook events endpoint
begin
  uri = URI("#{BASE_URL}/api/v1/admin/webhook_events?token=#{ADMIN_TOKEN}")
  response = Net::HTTP.get_response(uri)
  
  if response.code == '200'
    data = JSON.parse(response.body)
    puts "✅ Webhook events endpoint is accessible"
    puts "   Total events (24h): #{data['stats']['total_events_24h']}"
    puts "   Failed events (24h): #{data['stats']['failed_events_24h']}"
    
    if data['stats']['events_by_type'] && !data['stats']['events_by_type'].empty?
      puts "   Event types received:"
      data['stats']['events_by_type'].each do |type, count|
        puts "     - #{type}: #{count}"
      end
    else
      puts "   ⚠️  No webhook events received yet"
    end
    
    if data['recent_events'] && data['recent_events'].any?
      puts "\n   Recent events:"
      data['recent_events'].first(5).each do |event|
        puts "     - #{event['event_type']} (#{event['status']}) at #{event['created_at']}"
      end
    end
  elsif response.code == '401'
    puts "❌ Authentication failed - check your ADMIN_TOKEN"
    exit 1
  else
    puts "❌ Webhook events endpoint returned: #{response.code}"
    puts "   Body: #{response.body}"
  end
rescue => e
  puts "❌ Error checking webhook events: #{e.message}"
end

# Step 3: Check current PR data
begin
  uri = URI("#{BASE_URL}/api/v1/reviews")
  response = Net::HTTP.get_response(uri)
  
  if response.code == '200'
    data = JSON.parse(response.body)
    puts "\n✅ PR data endpoint is accessible"
    puts "   Open PRs: #{data['count']}"
    puts "   Backend Approved PRs: #{data['approved_count']}"
    puts "   Last updated: #{data['last_updated'] || 'Never'}"
  else
    puts "❌ PR data endpoint returned: #{response.code}"
  end
rescue => e
  puts "❌ Error checking PR data: #{e.message}"
end

puts "\n" + "=" * 50
puts "📋 Next Steps:"
puts "1. If you haven't configured the webhook in GitHub yet:"
puts "   - Go to https://github.com/department-of-veterans-affairs/vets-api/settings/hooks"
puts "   - Add webhook URL: #{BASE_URL}/api/v1/github_webhooks"
puts "   - Use secret: (from GITHUB_WEBHOOK_SECRET env var)"
puts "   - Select events: Pull requests, Reviews, Check runs/suites, Statuses"
puts
puts "2. Test the webhook by:"
puts "   - Creating a test PR or"
puts "   - Editing an existing PR title or"
puts "   - Running CI on a PR"
puts
puts "3. Check webhook deliveries in GitHub:"
puts "   - Look for green checkmarks in Recent Deliveries"
puts "   - Click any delivery to see request/response details"
puts
puts "4. Monitor events with:"
puts "   curl '#{BASE_URL}/api/v1/admin/webhook_events?token=#{ADMIN_TOKEN}'"
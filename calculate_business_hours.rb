#!/usr/bin/env ruby

# Calculate GitHub Actions minutes for business hours only
# Monday-Friday, 9AM-7PM EST, every 30 minutes

# Business hours setup
business_days_per_week = 5  # Monday through Friday
hours_per_day = 10  # 9AM to 7PM = 10 hours
runs_per_hour = 2  # Every 30 minutes
weeks_per_month = 4.33  # Average weeks in a month

# Calculate runs
runs_per_day = hours_per_day * runs_per_hour
runs_per_week = runs_per_day * business_days_per_week
runs_per_month = (runs_per_week * weeks_per_month).round

# From our previous test: ~3 minutes per run
minutes_per_run = 3
total_minutes_per_month = runs_per_month * minutes_per_run

# Cost calculation
free_tier_minutes = 2000
billable_minutes = [total_minutes_per_month - free_tier_minutes, 0].max
cost_per_minute = 0.008
monthly_cost = billable_minutes * cost_per_minute

puts "GitHub Actions Usage - Business Hours Only"
puts "=========================================="
puts "Schedule: Monday-Friday, 9AM-7PM EST, every 30 minutes"
puts ""
puts "Runs per day: #{runs_per_day}"
puts "Runs per week: #{runs_per_week}"
puts "Runs per month: #{runs_per_month}"
puts ""
puts "Minutes per run: #{minutes_per_run}"
puts "Total minutes per month: #{total_minutes_per_month}"
puts "Free tier (2000 minutes): #{total_minutes_per_month > 2000 ? 'EXCEEDED by ' + billable_minutes.to_s + ' minutes' : 'OK'}"
puts "Monthly cost: $#{monthly_cost.round(2)}"
puts ""
puts "Comparison to 24/7 every 15 minutes:"
puts "- 24/7 15min: 8,640 minutes/month ($53.12)"
puts "- Business hours 30min: #{total_minutes_per_month} minutes/month ($#{monthly_cost.round(2)})"
puts "- Savings: $#{(53.12 - monthly_cost).round(2)}/month"
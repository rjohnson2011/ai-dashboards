#!/usr/bin/env ruby
# Script to fetch recent PR activity including comments, commits, and deployments

require 'logger'
require 'time'

logger = Logger.new(STDOUT)

pr_number = ARGV[0]&.to_i || 22937
limit = ARGV[1]&.to_i || 10

logger.info "Fetching recent activity for PR ##{pr_number}"

begin
  github_service = GithubService.new
  client = github_service.instance_variable_get(:@client)
  owner = github_service.instance_variable_get(:@owner)
  repo = github_service.instance_variable_get(:@repo)
  
  # Get PR details
  pr = client.pull_request("#{owner}/#{repo}", pr_number)
  puts "\nPR ##{pr_number}: #{pr.title}"
  puts "Author: @#{pr.user.login}"
  puts "State: #{pr.state}"
  puts "="*80
  
  # Collect all activities with timestamps
  activities = []
  
  # 1. Get comments
  logger.info "Fetching comments..."
  comments = client.issue_comments("#{owner}/#{repo}", pr_number)
  comments.each do |comment|
    activities << {
      type: 'comment',
      time: comment.created_at,
      actor: comment.user.login,
      body: comment.body,
      html_url: comment.html_url
    }
  end
  
  # 2. Get review comments (inline code comments)
  logger.info "Fetching review comments..."
  review_comments = client.pull_request_comments("#{owner}/#{repo}", pr_number)
  review_comments.each do |comment|
    activities << {
      type: 'review_comment',
      time: comment.created_at,
      actor: comment.user.login,
      body: comment.body,
      path: comment.path,
      line: comment.line,
      html_url: comment.html_url
    }
  end
  
  # 3. Get reviews
  logger.info "Fetching reviews..."
  reviews = client.pull_request_reviews("#{owner}/#{repo}", pr_number)
  reviews.each do |review|
    activities << {
      type: 'review',
      time: review.submitted_at,
      actor: review.user.login,
      state: review.state,
      body: review.body
    }
  end
  
  # 4. Get commits
  logger.info "Fetching commits..."
  commits = client.pull_request_commits("#{owner}/#{repo}", pr_number)
  commits.each do |commit|
    activities << {
      type: 'commit',
      time: commit.commit.author.date,
      actor: commit.author&.login || commit.commit.author.name,
      sha: commit.sha,
      message: commit.commit.message
    }
  end
  
  # 5. Get events (labels, assignments, etc)
  logger.info "Fetching events..."
  events = client.issue_events("#{owner}/#{repo}", pr_number)
  events.each do |event|
    next unless event.created_at # Skip events without timestamps
    
    activities << {
      type: 'event',
      time: event.created_at,
      actor: event.actor&.login || 'system',
      event: event.event,
      label: event.label&.name,
      assignee: event.assignee&.login
    }
  end
  
  # Sort all activities by time and get the most recent
  sorted_activities = activities.sort_by { |a| a[:time] }.last(limit)
  
  logger.info "Found #{activities.count} total activities. Showing last #{sorted_activities.count}:"
  puts "\nRecent Activity (chronological order):"
  puts "="*80
  
  sorted_activities.each do |activity|
    time_str = activity[:time].localtime.strftime("%Y-%m-%d %H:%M:%S %Z")
    
    case activity[:type]
    when 'comment'
      puts "\n[#{time_str}] 💬 @#{activity[:actor]} commented:"
      body_preview = activity[:body].split("\n").first(3).join("\n  ")
      puts "  #{body_preview}"
      puts "  [... more ...]" if activity[:body].split("\n").length > 3
      puts "  Link: #{activity[:html_url]}" if activity[:html_url]
      
    when 'review_comment'
      puts "\n[#{time_str}] 📝 @#{activity[:actor]} commented on #{activity[:path]}:"
      puts "  Line #{activity[:line]}: #{activity[:body].split("\n").first}"
      
    when 'review'
      state_emoji = case activity[:state]
      when 'APPROVED' then '✅'
      when 'CHANGES_REQUESTED' then '❌'
      when 'COMMENTED' then '💭'
      else '👁️'
      end
      puts "\n[#{time_str}] #{state_emoji} @#{activity[:actor]} reviewed (#{activity[:state]})"
      puts "  #{activity[:body]}" if activity[:body] && !activity[:body].empty?
      
    when 'commit'
      puts "\n[#{time_str}] 🔨 @#{activity[:actor]} committed:"
      puts "  #{activity[:sha][0..7]}: #{activity[:message].split("\n").first}"
      
    when 'event'
      case activity[:event]
      when 'labeled'
        puts "\n[#{time_str}] 🏷️ @#{activity[:actor]} added label: #{activity[:label]}"
      when 'unlabeled'
        puts "\n[#{time_str}] 🏷️ @#{activity[:actor]} removed label: #{activity[:label]}"
      when 'assigned'
        puts "\n[#{time_str}] 👤 @#{activity[:actor]} assigned: @#{activity[:assignee]}"
      when 'closed'
        puts "\n[#{time_str}] ❌ @#{activity[:actor]} closed the PR"
      when 'reopened'
        puts "\n[#{time_str}] 🔓 @#{activity[:actor]} reopened the PR"
      else
        puts "\n[#{time_str}] ⚡ @#{activity[:actor]} - #{activity[:event]}"
      end
    end
  end
  
  puts "\n" + "="*80
  
  # Special section for deployment information
  puts "\nDeployment Information:"
  puts "="*80
  
  # Look for deployment-related comments (from va-vfs-bot)
  deployment_comments = comments.select { |c| 
    c.user.login.include?('bot') && 
    (c.body.include?('deployed') || c.body.include?('deployment'))
  }.last(5)
  
  if deployment_comments.any?
    deployment_comments.each do |comment|
      time_str = comment.created_at.localtime.strftime("%Y-%m-%d %H:%M:%S %Z")
      puts "\n[#{time_str}] 🚀 @#{comment.user.login}:"
      puts "  #{comment.body.strip}"
    end
  else
    puts "No recent deployment information found in comments."
  end
  
rescue => e
  logger.error "Error fetching activity: #{e.message}"
  logger.error e.backtrace.first(5).join("\n")
end
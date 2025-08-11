#!/usr/bin/env ruby
# Script to fetch PR timeline events from GitHub API

require 'logger'
require 'time'

logger = Logger.new(STDOUT)

pr_number = ARGV[0]&.to_i || 22937
limit = ARGV[1]&.to_i || 10

logger.info "Fetching timeline for PR ##{pr_number} (last #{limit} events)"

begin
  github_service = GithubService.new
  client = github_service.instance_variable_get(:@client)
  owner = github_service.instance_variable_get(:@owner)
  repo = github_service.instance_variable_get(:@repo)

  # Fetch timeline events - using issue_timeline method
  events = client.issue_timeline("#{owner}/#{repo}", pr_number, per_page: 100)

  # Sort by created_at and get the last N events
  sorted_events = events.sort_by { |e| e.created_at || Time.now }
  recent_events = sorted_events.last(limit)

  logger.info "Found #{events.count} total timeline events. Showing last #{recent_events.count}:"
  puts "\n" + "="*80

  recent_events.each do |event|
    time = event.created_at ? event.created_at.strftime("%Y-%m-%d %H:%M:%S") : "Unknown time"
    actor = event.actor&.login || event.user&.login || "Unknown"

    case event.event
    when 'commented'
      # Fetch the actual comment content
      comment_body = event.body || "No comment body"
      puts "\n[#{time}] 💬 @#{actor} commented:"
      puts "  #{comment_body.split("\n").first(3).join("\n  ")}"
      puts "  ..." if comment_body.split("\n").length > 3

    when 'committed'
      sha = event.sha || "unknown"
      message = event.message || "No commit message"
      puts "\n[#{time}] 📝 @#{actor} committed (#{sha[0..6]}):"
      puts "  #{message.split("\n").first}"

    when 'reviewed'
      state = event.state || "unknown"
      puts "\n[#{time}] 👁️ @#{actor} reviewed (#{state})"

    when 'labeled', 'unlabeled'
      label = event.label&.name || "unknown"
      action = event.event == 'labeled' ? 'added' : 'removed'
      puts "\n[#{time}] 🏷️ @#{actor} #{action} label: #{label}"

    when 'deployed'
      environment = event.deployment&.environment || "unknown"
      puts "\n[#{time}] 🚀 @#{actor} deployed to: #{environment}"

    when 'deployment_environment_changed'
      puts "\n[#{time}] 🔄 @#{actor} deployment environment changed"

    when 'head_ref_force_pushed'
      puts "\n[#{time}] 🔨 @#{actor} force pushed"

    when 'merged'
      puts "\n[#{time}] ✅ @#{actor} merged the PR"

    when 'closed'
      puts "\n[#{time}] ❌ @#{actor} closed the PR"

    when 'reopened'
      puts "\n[#{time}] 🔓 @#{actor} reopened the PR"

    when 'assigned', 'unassigned'
      assignee = event.assignee&.login || "unknown"
      action = event.event == 'assigned' ? 'assigned' : 'unassigned'
      puts "\n[#{time}] 👤 @#{actor} #{action}: @#{assignee}"

    when 'review_requested', 'review_request_removed'
      reviewer = event.requested_reviewer&.login || event.requested_team&.name || "unknown"
      action = event.event == 'review_requested' ? 'requested review from' : 'removed review request for'
      puts "\n[#{time}] 👀 @#{actor} #{action}: #{reviewer}"

    else
      puts "\n[#{time}] ❓ @#{actor} triggered: #{event.event}"
      # Print raw event data for unknown types
      puts "  Raw data: #{event.to_h.slice(:event, :state, :body).inspect}"
    end
  end

  puts "\n" + "="*80

  # Also fetch recent comments separately for more detail
  puts "\nRecent Comments:"
  comments = client.issue_comments("#{owner}/#{repo}", pr_number, per_page: 5, direction: 'desc')

  comments.reverse.each do |comment|
    time = comment.created_at.strftime("%Y-%m-%d %H:%M:%S")
    puts "\n[#{time}] @#{comment.user.login}:"
    puts comment.body.split("\n").map { |line| "  #{line}" }.join("\n")
  end

rescue => e
  logger.error "Error fetching timeline: #{e.message}"
  logger.error e.backtrace.first(5).join("\n")
end

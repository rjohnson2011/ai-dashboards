#!/usr/bin/env ruby
# Test cron job with hybrid checker for PR #23103

require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::INFO

logger.info "Testing cron job with hybrid checker"

begin
  # Initialize services
  github_service = GithubService.new
  hybrid_service = HybridPrCheckerService.new
  
  # Test on PR #23103
  pr = PullRequest.find_by(number: 23103)
  
  if pr
    logger.info "Testing hybrid checker for PR ##{pr.number}: #{pr.title[0..50]}..."
    
    # Get checks using hybrid service
    result = hybrid_service.get_accurate_pr_checks(pr)
    
    logger.info "Results:"
    logger.info "- Overall status: #{result[:overall_status]}"
    logger.info "- Total checks: #{result[:total_checks]}"
    logger.info "- Successful: #{result[:successful_checks]}"
    logger.info "- Failed: #{result[:failed_checks]}"
    logger.info "- Pending: #{result[:pending_checks]}"
    
    # Update PR
    pr.update!(
      ci_status: result[:overall_status] || 'unknown',
      total_checks: result[:total_checks] || 0,
      successful_checks: result[:successful_checks] || 0,
      failed_checks: result[:failed_checks] || 0
    )
    
    # Clear and save check runs
    pr.check_runs.destroy_all
    result[:checks].each do |check|
      pr.check_runs.create!(
        name: check[:name],
        status: check[:status] || 'unknown',
        url: check[:url],
        description: check[:description],
        required: check[:required] || false,
        suite_name: check[:suite_name]
      )
    end
    
    logger.info "Successfully updated PR and saved #{result[:checks].count} check runs"
  else
    logger.error "PR #23103 not found"
  end
  
rescue => e
  logger.error "Error: #{e.class} - #{e.message}"
  logger.error e.backtrace.first(5).join("\n")
end
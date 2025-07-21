#!/usr/bin/env ruby
# Debug script to compare different check methods

require 'logger'

logger = Logger.new(STDOUT)
pr_number = 23171

logger.info "Debugging checks for PR ##{pr_number}"

pr = PullRequest.find_by(number: pr_number)
unless pr
  logger.error "PR not found"
  exit
end

logger.info "PR: #{pr.title}"
logger.info "Head SHA: #{pr.head_sha}"

# Initialize services
github_service = GithubService.new
hybrid_service = HybridPrCheckerService.new
scraper_service = EnhancedGithubScraperService.new

# Get client for direct API calls
client = github_service.instance_variable_get(:@client)
owner = github_service.instance_variable_get(:@owner)
repo = github_service.instance_variable_get(:@repo)

logger.info "\n=== Direct API Calls ==="

# 1. Check runs
logger.info "\n1. Check Runs API:"
begin
  check_runs = client.check_runs_for_ref(
    "#{owner}/#{repo}", 
    pr.head_sha,
    accept: 'application/vnd.github.v3+json'
  )
  logger.info "Found #{check_runs.total_count} check runs"
  check_runs.check_runs.each do |run|
    logger.info "  - [#{run.status}] #{run.name}"
  end
rescue => e
  logger.error "Check runs error: #{e.message}"
end

# 2. Commit statuses
logger.info "\n2. Commit Statuses API:"
begin
  statuses = client.statuses("#{owner}/#{repo}", pr.head_sha)
  logger.info "Found #{statuses.count} commit statuses"
  statuses.each do |status|
    logger.info "  - [#{status.state}] #{status.context}"
  end
rescue => e
  logger.error "Statuses error: #{e.message}"
end

# 3. Combined status
logger.info "\n3. Combined Status API:"
begin
  combined = client.combined_status("#{owner}/#{repo}", pr.head_sha)
  logger.info "Overall state: #{combined.state}"
  logger.info "Total statuses: #{combined.statuses.count}"
  combined.statuses.each do |status|
    logger.info "  - [#{status.state}] #{status.context}"
  end
rescue => e
  logger.error "Combined status error: #{e.message}"
end

# 4. Check suites
logger.info "\n4. Check Suites API:"
begin
  suites = client.check_suites_for_ref(
    "#{owner}/#{repo}",
    pr.head_sha,
    accept: 'application/vnd.github.v3+json'
  )
  logger.info "Found #{suites.total_count} check suites"
  suites.check_suites.each do |suite|
    logger.info "  - [#{suite.status}] #{suite.app.name} (#{suite.conclusion || 'in progress'})"
  end
rescue => e
  logger.error "Check suites error: #{e.message}"
end

logger.info "\n=== Hybrid Service Results ==="
result = hybrid_service.get_accurate_pr_checks(pr)
logger.info "Total: #{result[:total_checks]} (#{result[:successful_checks]} success, #{result[:failed_checks]} failed, #{result[:pending_checks]} pending)"

logger.info "\n=== Scraper Service Results ==="
scraper_result = scraper_service.scrape_pr_checks_detailed(pr.url)
logger.info "Total: #{scraper_result[:total_checks]} (#{scraper_result[:successful_checks]} success, #{scraper_result[:failed_checks]} failed)"
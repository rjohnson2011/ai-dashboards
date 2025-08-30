#!/usr/bin/env ruby
# Quick PR Metadata Update - Updates PR titles, labels, and approvals without fetching checks
# This runs more frequently to keep basic PR info up to date

require 'logger'

logger = Logger.new(STDOUT)
logger.info "Starting Quick PR Metadata Update"

# Validate GitHub token
if ENV['GITHUB_TOKEN'].blank?
  logger.error "GITHUB_TOKEN environment variable is not set!"
  raise "GITHUB_TOKEN not configured"
end

begin
  # Ensure backend team members are populated
  backend_team_members = [
    'ericboehs', 'LindseySaari', 'rmtolmach', 'stiehlrod',
    'RachalCassity', 'rjohnson2011', 'stevenjcumming'
  ]
  
  backend_team_members.each do |username|
    BackendReviewGroupMember.find_or_create_by(username: username)
  end

  # Initialize GitHub service
  github_service = GithubService.new
  
  # Check rate limit
  rate_limit = github_service.rate_limit
  logger.info "GitHub API rate limit: #{rate_limit.remaining}/#{rate_limit.limit}"
  
  if rate_limit.remaining < 100
    logger.error "Low API rate limit (#{rate_limit.remaining}), exiting"
    exit 1
  end

  # Fetch all open PRs
  logger.info "Fetching open pull requests..."
  start_time = Time.now
  
  open_prs = github_service.all_pull_requests(state: 'open')
  logger.info "Found #{open_prs.count} open PRs (took #{(Time.now - start_time).round(2)}s)"

  # Get repository values
  repo_name = ENV['GITHUB_REPO'] || 'vets-api'
  repo_owner = ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs'
  has_repository_columns = PullRequest.column_names.include?("repository_name")

  # Update PR metadata
  updated_count = 0
  open_prs.each do |pr_data|
    pr = PullRequest.find_or_initialize_by(github_id: pr_data.id)
    
    # Set repository info for new records
    if pr.new_record? && has_repository_columns
      pr.repository_name = repo_name
      pr.repository_owner = repo_owner
    end

    # Update basic metadata
    update_attrs = {
      github_id: pr_data.id,
      number: pr_data.number,
      title: pr_data.title,
      author: pr_data.user.login,
      state: pr_data.state,
      url: pr_data.html_url,
      pr_created_at: pr_data.created_at,
      pr_updated_at: pr_data.updated_at,
      draft: pr_data.draft || false,
      labels: pr_data.labels.map { |label| label.name }
    }

    if has_repository_columns
      update_attrs[:repository_name] = repo_name
      update_attrs[:repository_owner] = repo_owner
    end

    if pr.has_attribute?(:head_sha)
      update_attrs[:head_sha] = pr_data.head.sha
    end

    pr.assign_attributes(update_attrs)
    pr.save!(validate: !has_repository_columns)
    updated_count += 1
  end

  logger.info "Updated #{updated_count} PR records"

  # Update reviews and approval statuses for all open PRs
  logger.info "Updating PR reviews and approval statuses..."
  review_errors = 0
  
  PullRequest.open.find_each do |pr|
    begin
      # Fetch reviews
      reviews = github_service.pull_request_reviews(pr.number)
      
      # Update reviews
      reviews.each do |review_data|
        PullRequestReview.find_or_create_by(
          pull_request_id: pr.id,
          github_id: review_data.id
        ).update!(
          user: review_data.user.login,
          state: review_data.state,
          submitted_at: review_data.submitted_at
        )
      end
      
      # Update approval statuses
      pr.update_backend_approval_status!
      pr.update_ready_for_backend_review!
      pr.update_approval_status!
      
    rescue => e
      logger.error "Error updating reviews for PR ##{pr.number}: #{e.message}"
      review_errors += 1
    end
  end

  # Update cache
  Rails.cache.write('last_metadata_refresh_time', Time.current)

  # Final stats
  total_time = Time.now - start_time
  final_rate_limit = github_service.rate_limit
  api_calls_used = rate_limit.remaining - final_rate_limit.remaining

  logger.info "="*60
  logger.info "Quick metadata update completed successfully!"
  logger.info "Total time: #{total_time.round(2)} seconds"
  logger.info "API calls used: #{api_calls_used}"
  logger.info "Remaining API calls: #{final_rate_limit.remaining}/#{final_rate_limit.limit}"
  logger.info "Review errors: #{review_errors}"
  logger.info "="*60

rescue => e
  logger.error "FATAL ERROR: #{e.class} - #{e.message}"
  logger.error e.backtrace&.first(10)&.join("\n")
  raise e
end
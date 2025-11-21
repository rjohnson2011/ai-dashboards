#!/usr/bin/env ruby
# Script to populate labels for existing PRs
# Run with: rails runner scripts/populate_labels.rb

require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::INFO

logger.info "Starting label population script..."

begin
  github_service = GithubService.new(
    owner: ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs',
    repo: ENV['GITHUB_REPO'] || 'vets-api'
  )

  # Check rate limit
  rate_limit = github_service.rate_limit
  logger.info "GitHub API rate limit: #{rate_limit.remaining}/#{rate_limit.limit}"

  if rate_limit.remaining < 100
    logger.error "Low API rate limit, exiting"
    exit 1
  end

  # Update labels for all open PRs
  updated_count = 0
  error_count = 0

  PullRequest.where(state: 'open').find_each.with_index do |pr, index|
    begin
      logger.info "[#{index + 1}] Updating PR ##{pr.number}..."

      # Fetch PR data from GitHub
      github_pr = github_service.pull_request(pr.number)

      if github_pr
        # Extract labels
        labels = github_pr.labels.map(&:name)

        # Update PR with labels
        pr.update!(
          labels: labels,
          pr_updated_at: github_pr.updated_at
        )

        updated_count += 1

        if labels.include?('exempt-be-review')
          logger.info "  ✓ PR ##{pr.number} has exempt-be-review label"
        end
      else
        logger.warn "  ✗ Could not fetch PR ##{pr.number} from GitHub"
        error_count += 1
      end

      # Rate limit pause every 30 requests
      if (index + 1) % 30 == 0
        logger.info "Pausing for rate limit..."
        sleep 2
      end

    rescue => e
      logger.error "  ✗ Error updating PR ##{pr.number}: #{e.message}"
      error_count += 1
    end
  end

  logger.info "=" * 60
  logger.info "Label population complete!"
  logger.info "Updated: #{updated_count} PRs"
  logger.info "Errors: #{error_count}"

  # Show PRs with exempt-be-review label
  exempt_prs = PullRequest.where(state: 'open').where("labels @> ?", '["exempt-be-review"]'.jsonb)
  logger.info "PRs with exempt-be-review label: #{exempt_prs.count}"

  exempt_prs.limit(5).each do |pr|
    logger.info "  - PR ##{pr.number}: #{pr.title}"
  end

rescue => e
  logger.error "FATAL ERROR: #{e.class} - #{e.message}"
  logger.error e.backtrace.first(5).join("\n")
  exit 1
end

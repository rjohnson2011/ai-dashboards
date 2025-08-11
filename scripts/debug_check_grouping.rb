#!/usr/bin/env ruby
# Debug how GitHub groups checks in the UI

require 'logger'

logger = Logger.new(STDOUT)
pr_number = 23171

pr = PullRequest.find_by(number: pr_number)
github_service = GithubService.new
client = github_service.instance_variable_get(:@client)
owner = github_service.instance_variable_get(:@owner)
repo = github_service.instance_variable_get(:@repo)

# Get all check runs with full details
check_runs = client.check_runs_for_ref(
  "#{owner}/#{repo}",
  pr.head_sha,
  accept: 'application/vnd.github.v3+json'
)

logger.info "Total check runs: #{check_runs.total_count}"

# Group by workflow/suite
workflow_groups = {}

check_runs.check_runs.each do |run|
  # Get workflow name from check suite
  workflow_name = if run.check_suite
    # Try to get workflow name from check suite
    suite_name = run.check_suite.app&.name || 'Unknown App'
    workflow_run_id = run.check_suite.id

    # For GitHub Actions, group by workflow
    if suite_name == 'GitHub Actions'
      # Extract workflow name from the URL or other metadata
      if run.html_url =~ /actions\/runs\/(\d+)/
        workflow_run_id = $1
      end
      workflow_key = "GitHub Actions - Run #{workflow_run_id}"
    else
      workflow_key = suite_name
    end
  else
    workflow_key = 'Other Checks'
  end

  workflow_groups[workflow_key] ||= []
  workflow_groups[workflow_key] << {
    name: run.name,
    status: run.status,
    conclusion: run.conclusion,
    url: run.html_url
  }
end

logger.info "\nGrouped by workflow:"
workflow_groups.each do |workflow, checks|
  logger.info "\n#{workflow} (#{checks.count} checks):"
  checks.each do |check|
    logger.info "  - [#{check[:conclusion] || check[:status]}] #{check[:name]}"
  end
end

# Count unique check names vs total
unique_names = check_runs.check_runs.map(&:name).uniq
logger.info "\nUnique check names: #{unique_names.count}"
logger.info "Total check runs: #{check_runs.total_count}"
logger.info "\nThis explains why deduping by name gives #{unique_names.count} but UI shows #{check_runs.total_count}"

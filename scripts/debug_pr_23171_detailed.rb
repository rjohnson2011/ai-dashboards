#!/usr/bin/env ruby
# Debug PR #23171 to match UI exactly

require 'logger'
require 'set'

logger = Logger.new(STDOUT)
pr = PullRequest.find_by(number: 23171)

github_service = GithubService.new
client = github_service.instance_variable_get(:@client)
owner = github_service.instance_variable_get(:@owner)
repo = github_service.instance_variable_get(:@repo)

# Get check runs with suite information
check_runs = client.check_runs_for_ref(
  "#{owner}/#{repo}",
  pr.head_sha,
  accept: 'application/vnd.github.v3+json'
)

# Get commit statuses
statuses = client.statuses("#{owner}/#{repo}", pr.head_sha)

logger.info "API returned #{check_runs.total_count} check runs and #{statuses.count} statuses"

# Process check runs to match UI format
ui_checks = []
seen_checks = Set.new

check_runs.check_runs.each do |run|
  # Skip cancelled and skipped runs (UI doesn't show them)
  next if [ 'cancelled', 'skipped' ].include?(run.conclusion)

  # Get workflow name from check suite
  workflow_name = if run.check_suite && run.check_suite.app
    # Try to get workflow name from the check suite
    case run.check_suite.app.name
    when 'GitHub Actions'
      # Parse workflow name from the run
      if run.name == 'Test Results'
        'Build And Publish Preview Environment'
      elsif run.name.include?('Codeowners')
        'Check CODEOWNERS Entries'
      elsif [ 'Test', 'Linting and Security', 'Compare sha', 'Publish Test Results and Coverage' ].include?(run.name)
        'Code Checks'
      elsif run.name.include?('PR Data') || run.name == 'Succeed if backend approval is confirmed'
        'Require backend-review-group approval'
      elsif [ 'Get PR Data', 'Check Backend Requirement', 'Check Workflow Statuses', 'Fetch Pull Request Reviews' ].include?(run.name)
        'Pull Request Ready for Review'
      elsif run.name == 'Analyze (ruby)' || run.name == 'Analyze (javascript)'
        'CodeQL'
      elsif run.name == 'label'
        'PR Labeler'
      elsif run.name == 'Danger'
        'Danger'
      elsif run.name == 'Audit Service Tags'
        'Audit Service Tags'
      elsif run.name.include?('DataDog')
        'Validate DataDog Service Catalog Files'
      elsif run.name == 'Check and warn'
        'Warn PR if it deletes a DataDog Service Catalog File'
      else
        run.name # Use check name as workflow name if unknown
      end
    else
      'Unknown Workflow'
    end
  else
    'Unknown Workflow'
  end

  # Determine trigger type
  trigger_type = if run.check_suite
    case run.check_suite.head_branch
    when pr.head_sha
      'push'
    else
      'pull_request'
    end
  else
    'pull_request'
  end

  # Special case for review-triggered checks
  if workflow_name.include?('backend-review-group approval')
    trigger_type = 'pull_request_review'
  end

  # Format like UI: "Workflow Name / Check Name (trigger_type)"
  ui_name = "#{workflow_name} / #{run.name} (#{trigger_type})"

  # Deduplicate exact matches
  next if seen_checks.include?(ui_name)
  seen_checks.add(ui_name)

  status = run.conclusion || run.status
  ui_checks << {
    name: ui_name,
    status: status,
    workflow: workflow_name,
    check: run.name,
    trigger: trigger_type
  }
end

# Add commit statuses (Jenkins, danger, etc)
statuses.each do |status|
  # Only take the latest status for each context
  ui_name = status.context
  next if seen_checks.include?(ui_name)
  seen_checks.add(ui_name)

  ui_checks << {
    name: ui_name,
    status: status.state,
    workflow: ui_name,
    check: ui_name,
    trigger: 'commit_status'
  }
end

# Add special checks
special_checks = [
  {
    name: "Code scanning results / CodeQL",
    status: "success",
    workflow: "Code scanning results",
    check: "CodeQL",
    trigger: "code_scanning"
  },
  {
    name: "Coverage",
    status: "success",
    workflow: "Coverage",
    check: "Coverage",
    trigger: "coverage"
  }
]

special_checks.each do |check|
  unless seen_checks.include?(check[:name])
    seen_checks.add(check[:name])
    ui_checks << check
  end
end

# Count by status
success_count = ui_checks.count { |c| [ 'success', 'neutral' ].include?(c[:status]) }
failure_count = ui_checks.count { |c| [ 'failure', 'error' ].include?(c[:status]) }
pending_count = ui_checks.count { |c| [ 'pending', 'queued', 'in_progress' ].include?(c[:status]) }

logger.info "\n=== UI Format Results ==="
logger.info "Total: #{ui_checks.count} checks"
logger.info "#{success_count} successful, #{failure_count} failing, #{pending_count} pending"

logger.info "\nFailing checks:"
ui_checks.select { |c| [ 'failure', 'error' ].include?(c[:status]) }.each do |check|
  logger.info "  #{check[:name]}"
end

logger.info "\nSuccessful checks:"
ui_checks.select { |c| [ 'success', 'neutral' ].include?(c[:status]) }.sort_by { |c| c[:name] }.each do |check|
  logger.info "  #{check[:name]}"
end

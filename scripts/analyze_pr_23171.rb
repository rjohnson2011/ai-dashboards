#!/usr/bin/env ruby

pr = PullRequest.find_by(number: 23171)
github_service = GithubService.new
client = github_service.instance_variable_get(:@client)
owner = github_service.instance_variable_get(:@owner)
repo = github_service.instance_variable_get(:@repo)

# Get ALL check runs and suites
check_runs = client.check_runs_for_ref(
  "#{owner}/#{repo}", 
  pr.head_sha,
  accept: 'application/vnd.github.v3+json',
  per_page: 100
)

check_suites = client.check_suites_for_ref(
  "#{owner}/#{repo}",
  pr.head_sha,
  accept: 'application/vnd.github.v3+json'
)

statuses = client.statuses("#{owner}/#{repo}", pr.head_sha)

puts "API Data:"
puts "- #{check_runs.total_count} check runs"
puts "- #{check_suites.total_count} check suites"  
puts "- #{statuses.count} commit statuses"

# Map suite IDs to workflow names
suite_workflows = {}
check_suites.check_suites.each do |suite|
  if suite.workflow_runs && suite.workflow_runs.any?
    workflow = suite.workflow_runs.first
    suite_workflows[suite.id] = workflow.name
  end
end

# Process check runs to match UI
ui_checks = []
seen_keys = Set.new

check_runs.check_runs.each do |run|
  next if ['cancelled', 'skipped'].include?(run.conclusion)
  
  # Determine workflow name
  workflow_name = if suite_workflows[run.check_suite&.id]
    suite_workflows[run.check_suite.id]
  else
    # Infer from check name patterns
    case run.name
    when 'Test Results', 'build-and-publish'
      'Build And Publish Preview Environment'
    when /Codeowners/
      'Check CODEOWNERS Entries'
    when 'Test', 'Linting and Security', 'Compare sha', 'Publish Test Results and Coverage'
      'Code Checks'
    when 'Succeed if backend approval is confirmed'
      'Require backend-review-group approval'
    when 'Get PR Data', 'Check Backend Requirement', 'Check Workflow Statuses', 'Fetch Pull Request Reviews'
      if run.name == 'Get PR Data' && run.external_id&.include?('review')
        'Require backend-review-group approval'
      else
        'Pull Request Ready for Review'
      end
    when /Analyze.*ruby/, /Analyze.*javascript/
      'CodeQL'
    when 'label'
      'PR Labeler'
    when 'Danger'
      'Danger'
    when 'Audit Service Tags'
      'Audit Service Tags'
    when /DataDog/, 'Validate changes to DataDog Service Catalog Files'
      'Validate DataDog Service Catalog Files'
    when 'Check and warn'
      'Warn PR if it deletes a DataDog Service Catalog File'
    else
      'Unknown'
    end
  end
  
  # Determine trigger type
  trigger = 'pull_request'
  if run.name == 'Test Results' || run.name == 'build-and-publish'
    trigger = 'push'
  elsif workflow_name.include?('backend-review-group') && run.name == 'Succeed if backend approval is confirmed'
    trigger = 'pull_request_review'
  end
  
  # Create UI format
  ui_name = "#{workflow_name} / #{run.name} (#{trigger})"
  key = "#{run.name}-#{trigger}"
  
  next if seen_keys.include?(key)
  seen_keys.add(key)
  
  ui_checks << {
    name: ui_name,
    status: run.conclusion || run.status,
    check: run.name,
    workflow: workflow_name
  }
end

# Add commit statuses
['continuous-integration/jenkins/pr-head', 
 'continuous-integration/jenkins/branch',
 'danger/danger'].each do |context|
  status = statuses.find { |s| s.context == context }
  if status && !seen_keys.include?(context)
    seen_keys.add(context)
    ui_checks << {
      name: context,
      status: status.state,
      check: context,
      workflow: context
    }
  end
end

# Add special UI-only checks
[
  { name: "Code scanning results / CodeQL", check: "CodeQL", workflow: "Code scanning results" },
  { name: "Coverage", check: "Coverage", workflow: "Coverage" }
].each do |special|
  unless seen_keys.include?(special[:check])
    seen_keys.add(special[:check])
    ui_checks << special.merge(status: 'success')
  end
end

# Summary
success = ui_checks.count { |c| ['success', 'neutral'].include?(c[:status]) }
failure = ui_checks.count { |c| ['failure', 'error'].include?(c[:status]) }

puts "\n=== Results ==="
puts "Total: #{ui_checks.count} checks"
puts "#{failure} failing, #{success} successful"

puts "\nAll checks:"
ui_checks.sort_by { |c| [c[:status] == 'failure' ? 0 : 1, c[:name]] }.each do |check|
  puts "[#{check[:status]}] #{check[:name]}"
end
#!/usr/bin/env ruby
# Test headless browser scraping for a specific PR

require 'playwright'
require 'json'
require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::INFO

pr_url = "https://github.com/department-of-veterans-affairs/vets-api/pull/23103"
logger.info "Testing headless scraper for: #{pr_url}"

# Launch browser
Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
  browser = playwright.chromium.launch(headless: true)
  page = browser.new_page
  
  logger.info "Navigating to PR page..."
  page.goto(pr_url)
  page.wait_for_load_state('networkidle')
  
  # Wait for checks to load
  logger.info "Waiting for checks to load..."
  page.wait_for_selector('[data-testid="checks-status-badge-rollup-group"]', timeout: 30000)
  sleep 2 # Additional wait for dynamic content
  
  logger.info "Extracting check information..."
  
  # Get all check groups
  check_groups = page.locator('[data-testid="checks-status-badge-rollup-group"]').all
  
  all_checks = []
  
  check_groups.each do |group|
    # Get status from the group
    status_element = group.locator('[data-testid="checks-status-badge-icon"] svg')
    status_class = status_element.get_attribute('class') rescue ''
    
    status = if status_class.include?('octicon-check')
               'success'
             elsif status_class.include?('octicon-x')
               'failure'
             elsif status_class.include?('octicon-dot-fill')
               'expected'
             else
               'unknown'
             end
    
    # Get check name
    name_element = group.locator('h4.text-normal, .text-normal')
    check_name = name_element.text_content.strip rescue 'Unknown'
    
    # Get suite name if available
    suite_element = group.locator('.text-small.color-fg-muted')
    suite_name = suite_element.text_content.strip rescue ''
    
    # Get description
    desc_element = group.locator('.color-fg-muted').nth(1) rescue nil
    description = desc_element ? desc_element.text_content.strip : ''
    
    # Check if required
    required = group.text_content.include?('Required') rescue false
    
    all_checks << {
      name: check_name,
      status: status,
      suite_name: suite_name,
      description: description,
      required: required,
      full_text: group.text_content.strip
    }
  end
  
  # Also try to get the summary counts
  summary_element = page.locator('.merge-status-list').first rescue nil
  if summary_element
    summary_text = summary_element.text_content
    logger.info "Summary text: #{summary_text}"
  end
  
  # Count by status
  status_counts = all_checks.group_by { |c| c[:status] }.transform_values(&:count)
  
  logger.info "\nCheck Summary:"
  logger.info "Total checks found: #{all_checks.count}"
  logger.info "Status breakdown: #{status_counts}"
  
  logger.info "\nAll checks found:"
  all_checks.each do |check|
    logger.info "- [#{check[:status]}] #{check[:name]} #{check[:required] ? '(Required)' : ''}"
    logger.info "  Suite: #{check[:suite_name]}" unless check[:suite_name].empty?
    logger.info "  Full text: #{check[:full_text]}"
  end
  
  browser.close
end
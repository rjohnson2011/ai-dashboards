#!/usr/bin/env ruby
# Test headless browser scraping for PR #23171

require 'playwright'
require 'json'
require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::INFO

pr_url = "https://github.com/department-of-veterans-affairs/vets-api/pull/23171"
logger.info "Testing headless scraper for PR #23171"

# Launch browser
Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
  browser = playwright.chromium.launch(headless: true)
  page = browser.new_page
  
  logger.info "Navigating to PR page..."
  page.goto(pr_url)
  
  # Wait for checks to load
  logger.info "Waiting for checks section..."
  begin
    # Try multiple possible selectors
    page.wait_for_selector('.merge-status-list', timeout: 10000) rescue nil
    page.wait_for_selector('[data-testid="checks-status-badge-rollup-group"]', timeout: 5000) rescue nil
    page.wait_for_selector('.checks-list-item', timeout: 5000) rescue nil
  rescue
    logger.warn "Timeout waiting for checks - continuing anyway"
  end
  
  # Additional wait for dynamic content
  sleep 3
  
  logger.info "Extracting check information..."
  
  # Method 1: Try to find the summary text
  summary_text = page.evaluate(<<~JS)
    (() => {
      // Look for summary text patterns
      const elements = document.querySelectorAll('*');
      for (const el of elements) {
        const text = el.textContent || '';
        if (text.match(/\\d+\\s+successful.*\\d+\\s+failing.*checks/) || 
            text.match(/\\d+\\s+failing.*\\d+\\s+successful.*checks/)) {
          return text.trim();
        }
      }
      return null;
    })()
  JS
  
  logger.info "Summary text found: #{summary_text}" if summary_text
  
  # Method 2: Get all visible check items
  all_checks = page.evaluate(<<~JS)
    (() => {
      const checks = [];
      
      // Try multiple selectors
      const selectors = [
        '[data-testid="checks-status-badge-rollup-group"]',
        '.checks-list-item',
        '.merge-status-item',
        '.status-check'
      ];
      
      for (const selector of selectors) {
        const items = document.querySelectorAll(selector);
        if (items.length > 0) {
          items.forEach(item => {
            // Get check name
            const nameEl = item.querySelector('h4, .text-normal, .merge-status-item-text, strong');
            const name = nameEl ? nameEl.textContent.trim() : '';
            
            // Get status - look for SVG icons
            let status = 'unknown';
            const svgs = item.querySelectorAll('svg');
            svgs.forEach(svg => {
              const classes = svg.getAttribute('class') || '';
              if (classes.includes('octicon-check')) status = 'success';
              else if (classes.includes('octicon-x')) status = 'failure';
              else if (classes.includes('octicon-dot-fill')) status = 'pending';
            });
            
            // Also check for color classes
            if (item.classList.contains('color-fg-success') || 
                item.querySelector('.color-fg-success')) {
              status = 'success';
            } else if (item.classList.contains('color-fg-danger') || 
                       item.querySelector('.color-fg-danger')) {
              status = 'failure';
            }
            
            // Get full text
            const fullText = item.textContent.trim();
            
            if (name) {
              checks.push({
                name: name,
                status: status,
                fullText: fullText,
                selector: selector
              });
            }
          });
          break; // Use first selector that returns results
        }
      }
      
      return checks;
    })()
  JS
  
  # Method 3: Count status icons directly
  icon_counts = page.evaluate(<<~JS)
    (() => {
      const counts = {
        success: 0,
        failure: 0,
        pending: 0
      };
      
      // Count octicon SVGs
      document.querySelectorAll('svg.octicon-check').forEach(() => counts.success++);
      document.querySelectorAll('svg.octicon-x').forEach(() => counts.failure++);
      document.querySelectorAll('svg.octicon-dot-fill').forEach(() => counts.pending++);
      
      return counts;
    })()
  JS
  
  # Method 4: Get the merge box status
  merge_box_text = page.evaluate(<<~JS)
    (() => {
      const mergeBox = document.querySelector('.branch-action-item, .merge-box, .merge-status-list');
      return mergeBox ? mergeBox.textContent.trim() : null;
    })()
  JS
  
  logger.info "\n=== Results ==="
  logger.info "Summary text: #{summary_text}"
  logger.info "\nIcon counts:"
  logger.info "- Success (checkmarks): #{icon_counts['success']}"
  logger.info "- Failure (X marks): #{icon_counts['failure']}"
  logger.info "- Pending (dots): #{icon_counts['pending']}"
  
  logger.info "\nChecks found: #{all_checks.length}"
  
  # Group by status
  by_status = all_checks.group_by { |c| c['status'] }
  logger.info "\nBy status:"
  by_status.each do |status, checks|
    logger.info "#{status.upcase}: #{checks.length}"
    checks.each do |check|
      logger.info "  - #{check['name']}"
    end
  end
  
  logger.info "\nMerge box text snippet: #{merge_box_text[0..200]}..." if merge_box_text
  
  # Save screenshot for debugging
  page.screenshot(path: 'pr_23171_checks.png')
  logger.info "\nScreenshot saved to pr_23171_checks.png"
  
  browser.close
end
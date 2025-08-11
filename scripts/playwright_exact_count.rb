#!/usr/bin/env ruby
# Get exact check counts using Playwright

require 'playwright'
require 'logger'

logger = Logger.new(STDOUT)
pr_url = "https://github.com/department-of-veterans-affairs/vets-api/pull/23171"

Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
  browser = playwright.chromium.launch(headless: false) # Use headful for debugging
  page = browser.new_page

  logger.info "Navigating to: #{pr_url}"
  page.goto(pr_url)

  # Wait for the merge status area
  page.wait_for_selector('.merge-status-list, .branch-action-item', timeout: 30000)
  sleep 5 # Extra time for all checks to load

  # Get all text that contains check counts
  count_texts = page.evaluate(<<~JS)
    (() => {
      const results = [];
    #{'  '}
      // Look for text patterns like "X successful, Y failing"
      const allText = document.body.innerText;
      const patterns = [
        /(\d+)\s+successful[^,]*,\s*(\d+)\s+failing/gi,
        /(\d+)\s+failing[^,]*,\s*(\d+)\s+successful/gi,
        /(\d+)\s+successful.*checks/gi,
        /All checks have passed/gi,
        /Some checks were not successful/gi
      ];
    #{'  '}
      patterns.forEach(pattern => {
        const matches = allText.matchAll(pattern);
        for (const match of matches) {
          results.push({
            text: match[0],
            numbers: [match[1], match[2]].filter(Boolean)
          });
        }
      });
    #{'  '}
      // Also get the merge status area specifically
      const mergeArea = document.querySelector('.merge-status-list, .merge-message, .branch-action-item');
      if (mergeArea) {
        results.push({
          mergeAreaText: mergeArea.innerText
        });
      }
    #{'  '}
      // Count visible check items
      const checkItems = document.querySelectorAll(
        '.merge-status-item:not(.d-none):not(.hidden), ' +
        '[data-testid="checks-status-badge-rollup-group"]:not(.d-none):not(.hidden)'
      );
    #{'  '}
      results.push({
        visibleCheckCount: checkItems.length
      });
    #{'  '}
      return results;
    })()
  JS

  logger.info "\nResults:"
  count_texts.each do |result|
    logger.info result.to_s
  end

  # Take screenshot of the checks area
  merge_element = page.locator('.merge-status-list, .branch-action-item').first
  if merge_element
    merge_element.screenshot(path: 'pr_23171_merge_area.png')
    logger.info "\nScreenshot of merge area saved"
  end

  # Wait a bit before closing
  sleep 3
  browser.close
end

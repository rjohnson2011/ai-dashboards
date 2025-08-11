require "playwright"

class PlaywrightScraperService
  def initialize
    @logger = Logger.new(STDOUT)
  end

  def scrape_pr_checks_detailed(pr_url)
    start_time = Time.now
    result = {
      overall_status: "unknown",
      total_checks: 0,
      successful_checks: 0,
      failed_checks: 0,
      pending_checks: 0,
      checks: []
    }

    Playwright.create(playwright_cli_executable_path: "npx playwright") do |playwright|
      browser = playwright.chromium.launch(headless: true)

      begin
        page = browser.new_page

        # Navigate to PR page
        @logger.info "Navigating to: #{pr_url}"
        page.goto(pr_url)

        # Wait for the page to be fully loaded
        page.wait_for_load_state

        # Wait for checks to appear - try multiple selectors
        checks_found = false

        # Try to find check elements with various selectors
        [ '[data-testid="check-run-item"]', ".merge-status-item", ".branch-action-item" ].each do |selector|
          begin
            page.wait_for_selector(selector, timeout: 5000)
            checks_found = true
            @logger.info "Found checks using selector: #{selector}"
            break
          rescue
            # Try next selector
          end
        end

        # Additional wait for dynamic content
        sleep 2

        # Extract check data
        checks_data = extract_checks_data(page)

        if checks_data[:checks].any?
          result[:checks] = checks_data[:checks]
          result[:total_checks] = checks_data[:total]
          result[:successful_checks] = checks_data[:successful]
          result[:failed_checks] = checks_data[:failed]
          result[:pending_checks] = checks_data[:pending]

          # Determine overall status
          if checks_data[:failed] > 0
            result[:overall_status] = "failure"
          elsif checks_data[:pending] > 0
            result[:overall_status] = "pending"
          elsif checks_data[:successful] > 0
            result[:overall_status] = "success"
          end
        end

        @logger.info "Scraped #{pr_url} in #{(Time.now - start_time).round(2)}s - Found #{result[:total_checks]} checks"

      ensure
        browser.close
      end
    end

    result
  rescue => e
    @logger.error "Error scraping #{pr_url}: #{e.class} - #{e.message}"
    @logger.error e.backtrace.first(5).join("\n")
    result
  end

  private

  def extract_checks_data(page)
    checks = []
    total = 0
    successful = 0
    failed = 0
    pending = 0

    # Look for various check elements
    selectors = [
      '[data-testid="check-run-item"]',
      ".merge-status-item",
      ".branch-action-item",
      ".status-check"
    ]

    selectors.each do |selector|
      elements = page.query_selector_all(selector)
      next if elements.empty?

      @logger.info "Found #{elements.length} elements with selector: #{selector}"

      elements.each do |element|
        begin
          text = element.text_content
          next if text.nil? || text.strip.empty?

          # Try to extract check name
          name = text.strip.split("\n").first

          # Determine status from text content
          status = if text.include?("Successful") || text.include?("Success") || text.include?("✓")
            "success"
          elsif text.include?("Failed") || text.include?("Failure") || text.include?("✗")
            "failure"
          elsif text.include?("Pending") || text.include?("In progress") || text.include?("Queued")
            "pending"
          else
            "unknown"
          end

          checks << {
            name: name,
            status: status,
            required: text.include?("Required")
          }

          case status
          when "success" then successful += 1
          when "failure" then failed += 1
          when "pending" then pending += 1
          end

          total += 1
        rescue => e
          @logger.warn "Error parsing element: #{e.message}"
        end
      end

      break if checks.any? # Stop if we found checks
    end

    # If no individual checks found, try to find summary text
    if checks.empty?
      summary_element = page.query_selector(".merge-status-list-summary, .branch-action-item-summary")
      if summary_element
        summary_text = summary_element.text_content
        @logger.info "Found summary text: #{summary_text}"

        # Parse numbers from summary
        if summary_text =~ /(\d+)\s+checks?\s+pass/i
          successful = $1.to_i
        end
        if summary_text =~ /(\d+)\s+successful/i
          successful = $1.to_i
        end
        if summary_text =~ /(\d+)\s+fail/i
          failed = $1.to_i
        end
        if summary_text =~ /(\d+)\s+pending/i
          pending = $1.to_i
        end

        total = successful + failed + pending

        # Create placeholder checks based on counts
        successful.times { checks << { name: "Check", status: "success", required: false } }
        failed.times { checks << { name: "Check", status: "failure", required: false } }
        pending.times { checks << { name: "Check", status: "pending", required: false } }
      end
    end

    @logger.info "Extracted #{total} checks: #{successful} successful, #{failed} failed, #{pending} pending"

    {
      checks: checks,
      total: total,
      successful: successful,
      failed: failed,
      pending: pending
    }
  end
end

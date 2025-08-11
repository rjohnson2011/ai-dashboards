require "selenium-webdriver"
require "nokogiri"

class JavascriptGithubScraperService
  def initialize
    @base_url = "https://github.com"
  end

  def scrape_pr_checks_with_js(pr_url)
    # Set up Chrome in headless mode
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument("--headless")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=1920,1080")
    options.add_argument("user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")

    # Add GitHub credentials if available
    if ENV["GITHUB_USERNAME"] && ENV["GITHUB_PASSWORD"]
      Rails.logger.info "[Scraper] Using GitHub credentials for authenticated scraping"
    end

    driver = Selenium::WebDriver.for :chrome, options: options

    begin
      # Navigate to the checks page instead of main PR page
      checks_url = pr_url + "/checks"
      Rails.logger.info "[Scraper] Loading PR checks page: #{checks_url}"
      driver.get(checks_url)

      # Wait for the merge status to load
      wait = Selenium::WebDriver::Wait.new(timeout: 20)

      # Look for the merge status section
      Rails.logger.info "[Scraper] Waiting for merge status to load..."
      begin
        wait.until { driver.find_element(css: ".merge-status-list, .branch-action-item, .js-details-container") }
      rescue Selenium::WebDriver::Error::TimeoutError
        Rails.logger.warn "[Scraper] Timeout waiting for merge status, continuing anyway"
      end

      # Extra wait for dynamic content
      sleep 3

      # Save screenshot for debugging
      driver.save_screenshot("pr_checks_screenshot.png")
      Rails.logger.info "[Scraper] Saved screenshot to pr_checks_screenshot.png"

      # Get the page source after JavaScript has loaded
      page_source = driver.page_source
      doc = Nokogiri::HTML(page_source)

      # Save HTML for analysis
      File.write("pr_checks_loaded.html", page_source)
      Rails.logger.info "[Scraper] Saved HTML to pr_checks_loaded.html"

      # Look for check summary in various locations
      check_summary = find_check_summary(doc)

      if check_summary
        Rails.logger.info "[Scraper] Found check summary: #{check_summary.inspect}"
        {
          overall_status: check_summary[:overall_status],
          checks: [],
          total_checks: check_summary[:total],
          successful_checks: check_summary[:successful],
          failed_checks: check_summary[:failed]
        }
      else
        Rails.logger.warn "[Scraper] No check summary found, falling back to counting"
        # Count individual checks as fallback
        count_individual_checks(doc)
      end

    rescue => e
      Rails.logger.error "[Scraper] Error scraping with JavaScript: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      {
        overall_status: "unknown",
        checks: [],
        total_checks: 0,
        successful_checks: 0,
        failed_checks: 0
      }
    ensure
      driver.quit if driver
    end
  end

  private

  def find_check_summary(doc)
    # Look for patterns like "1 failing, 23 successful checks"
    # or "1 pending, 23 successful checks"

    # Check in merge status area
    doc.css(".merge-status-item, .merge-status-list, .branch-action-item").each do |element|
      text = element.text.strip.gsub(/\s+/, " ")

      # Pattern: X failing, Y successful checks
      if match = text.match(/(\d+)\s+failing,\s+(\d+)\s+successful\s+checks?/i)
        return {
          failed: match[1].to_i,
          successful: match[2].to_i,
          total: match[1].to_i + match[2].to_i,
          overall_status: "failure"
        }
      end

      # Pattern: X pending, Y successful checks
      if match = text.match(/(\d+)\s+pending,\s+(\d+)\s+successful\s+checks?/i)
        return {
          failed: 0,
          pending: match[1].to_i,
          successful: match[2].to_i,
          total: match[1].to_i + match[2].to_i,
          overall_status: "pending"
        }
      end

      # Pattern: X successful checks (all passing)
      if match = text.match(/(\d+)\s+successful\s+checks?/i) && !text.include?("failing") && !text.include?("pending")
        return {
          failed: 0,
          successful: match[1].to_i,
          total: match[1].to_i,
          overall_status: "success"
        }
      end
    end

    # Also check in any element with merge or status related classes
    doc.css('[class*="merge"], [class*="status"], [class*="check"]').each do |element|
      text = element.text.strip.gsub(/\s+/, " ")

      if text.match(/\d+\s+(failing|pending|successful)/) && text.include?("check")
        Rails.logger.info "[Scraper] Found potential summary text: #{text}"

        # Try the same patterns
        if match = text.match(/(\d+)\s+failing,\s+(\d+)\s+successful\s+checks?/i)
          return {
            failed: match[1].to_i,
            successful: match[2].to_i,
            total: match[1].to_i + match[2].to_i,
            overall_status: "failure"
          }
        end

        if match = text.match(/(\d+)\s+pending,\s+(\d+)\s+successful\s+checks?/i)
          return {
            failed: 0,
            pending: match[1].to_i,
            successful: match[2].to_i,
            total: match[1].to_i + match[2].to_i,
            overall_status: "pending"
          }
        end
      end
    end

    nil
  end

  def count_individual_checks(doc)
    # Count checks by looking for status icons
    successful = doc.css(".octicon-check, .color-fg-success").size
    failed = doc.css(".octicon-x, .color-fg-danger").size
    pending = doc.css(".octicon-dot-fill, .color-fg-attention").size

    total = successful + failed + pending

    overall_status = if failed > 0
      "failure"
    elsif pending > 0
      "pending"
    elsif successful > 0
      "success"
    else
      "unknown"
    end

    {
      overall_status: overall_status,
      checks: [],
      total_checks: total,
      successful_checks: successful,
      failed_checks: failed
    }
  end
end

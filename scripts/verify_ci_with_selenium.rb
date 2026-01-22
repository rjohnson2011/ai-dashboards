#!/usr/bin/env ruby
# Selenium-based CI verification script
# Runs in GitHub Actions to verify CI status matches what's shown on GitHub UI
# This provides cross-verification between our API-based data and the actual rendered UI

# Force unbuffered output for GHA logs
$stdout.sync = true
$stderr.sync = true

require "selenium-webdriver"
require "nokogiri"
require "httparty"
require "json"

class SeleniumCiVerifier
  def initialize
    @api_url = ENV["API_URL"] || "https://ai-dashboards.onrender.com"
    @admin_token = ENV["ADMIN_TOKEN"]
    @github_owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
    @github_repo = ENV["GITHUB_REPO"] || "vets-api"
    @discrepancies = []
  end

  def run(sample_size: 10)
    puts "Starting Selenium CI verification..."
    puts "API URL: #{@api_url}"
    puts "Sample size: #{sample_size}"

    # Get PRs from our API
    prs = fetch_prs_from_api
    puts "Found #{prs.length} open PRs in our database"

    # Sample PRs to verify (prioritize those with failures)
    prs_to_verify = select_prs_to_verify(prs, sample_size)
    puts "Verifying #{prs_to_verify.length} PRs..."

    # Set up Selenium
    driver = setup_driver

    begin
      prs_to_verify.each_with_index do |pr, index|
        puts "\n[#{index + 1}/#{prs_to_verify.length}] Verifying PR ##{pr["number"]}..."
        verify_pr(driver, pr)
        sleep 2 # Rate limit protection
      end
    ensure
      driver.quit if driver
    end

    # Report results
    report_results

    # If discrepancies found, trigger fix via API
    if @discrepancies.any?
      puts "\nTriggering auto-fix for #{@discrepancies.length} discrepancies..."
      trigger_fix
    end

    puts "\nVerification complete!"
    @discrepancies.empty? ? 0 : 1
  end

  private

  def fetch_prs_from_api
    # Wake up the server first (Render free tier sleeps after inactivity)
    puts "Waking up API server..."
    3.times do |attempt|
      begin
        wake_response = HTTParty.get("#{@api_url}/api/v1/health", timeout: 30)
        if wake_response.success?
          puts "Server is awake!"
          break
        end
      rescue => e
        puts "Wake attempt #{attempt + 1} failed: #{e.message}"
        sleep 5
      end
    end

    # Now fetch PRs
    response = HTTParty.get(
      "#{@api_url}/api/v1/reviews",
      query: {
        repository_name: @github_repo,
        repository_owner: @github_owner
      },
      timeout: 120
    )

    if response.success?
      JSON.parse(response.body)
    else
      puts "Error fetching PRs: #{response.code}"
      []
    end
  rescue => e
    puts "Error fetching PRs: #{e.message}"
    []
  end

  def select_prs_to_verify(prs, sample_size)
    # Prioritize:
    # 1. PRs with CI failures (most important to verify)
    # 2. PRs with pending CI
    # 3. Recent PRs

    failing = prs.select { |pr| pr["ci_status"] == "failure" }
    pending = prs.select { |pr| pr["ci_status"] == "pending" }
    others = prs - failing - pending

    selected = []
    selected.concat(failing.first(sample_size / 2))
    selected.concat(pending.first(sample_size / 4))
    remaining = sample_size - selected.length
    selected.concat(others.first(remaining))

    selected.first(sample_size)
  end

  def setup_driver
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument("--headless")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=1920,1080")
    options.add_argument("user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")

    Selenium::WebDriver.for :chrome, options: options
  end

  def verify_pr(driver, pr)
    pr_url = pr["url"]
    pr_number = pr["number"]
    stored_ci_status = pr["ci_status"]
    stored_failed_checks = pr["failed_checks"].to_i

    begin
      # Navigate to PR checks page
      checks_url = "#{pr_url}/checks"
      driver.get(checks_url)

      # Wait for page to load
      sleep 3

      # Get the page source after JS renders
      page_source = driver.page_source
      doc = Nokogiri::HTML(page_source)

      # Extract CI status from rendered page
      ui_status = extract_ci_status_from_ui(doc)

      puts "  Stored: ci_status=#{stored_ci_status}, failed_checks=#{stored_failed_checks}"
      puts "  UI:     ci_status=#{ui_status[:status]}, failed_checks=#{ui_status[:failed]}"

      # Compare
      has_discrepancy = false

      # Check status mismatch (allow some tolerance)
      if status_mismatch?(stored_ci_status, ui_status[:status])
        has_discrepancy = true
        puts "  ⚠️  STATUS MISMATCH: stored=#{stored_ci_status}, ui=#{ui_status[:status]}"
      end

      # Check failed count mismatch (with tolerance of 2)
      if (stored_failed_checks - ui_status[:failed]).abs > 2
        has_discrepancy = true
        puts "  ⚠️  FAILED COUNT MISMATCH: stored=#{stored_failed_checks}, ui=#{ui_status[:failed]}"
      end

      if has_discrepancy
        @discrepancies << {
          pr_number: pr_number,
          pr_url: pr_url,
          stored: {
            ci_status: stored_ci_status,
            failed_checks: stored_failed_checks
          },
          ui: ui_status
        }
      else
        puts "  ✓ OK"
      end

    rescue => e
      puts "  Error verifying PR ##{pr_number}: #{e.message}"
    end
  end

  def extract_ci_status_from_ui(doc)
    # Look for check summary text
    status = "unknown"
    failed = 0
    successful = 0
    pending = 0

    # Pattern 1: Look for merge status summary
    doc.css(".merge-status-item, .branch-action-item, .js-merge-box-button").each do |element|
      text = element.text.strip.gsub(/\s+/, " ")

      # "X failing, Y successful checks"
      if match = text.match(/(\d+)\s+failing.*?(\d+)\s+successful/i)
        failed = match[1].to_i
        successful = match[2].to_i
        status = "failure"
        break
      end

      # "X pending, Y successful checks"
      if match = text.match(/(\d+)\s+pending.*?(\d+)\s+successful/i)
        pending = match[1].to_i
        successful = match[2].to_i
        status = "pending"
        break
      end

      # "All checks have passed"
      if text.match(/all.*checks.*passed/i) || text.match(/(\d+)\s+successful\s+checks?/i)
        if match = text.match(/(\d+)\s+successful/)
          successful = match[1].to_i
        end
        status = "success"
        break
      end
    end

    # Pattern 2: Count individual check icons if summary not found
    if status == "unknown"
      # Count by icon types
      failed = doc.css(".octicon-x, .color-fg-danger, [aria-label*='failing']").size
      successful = doc.css(".octicon-check, .color-fg-success, [aria-label*='passing']").size
      pending = doc.css(".octicon-dot-fill, .color-fg-attention, [aria-label*='pending']").size

      if failed > 0
        status = "failure"
      elsif pending > 0
        status = "pending"
      elsif successful > 0
        status = "success"
      end
    end

    {
      status: status,
      failed: failed,
      successful: successful,
      pending: pending,
      total: failed + successful + pending
    }
  end

  def status_mismatch?(stored, ui)
    # Allow some tolerance for timing differences
    return false if stored == ui
    return false if stored == "pending" && ui == "success" # Checks completed
    return false if stored == "unknown" || ui == "unknown"

    # Real mismatch: one says success, other says failure
    (stored == "success" && ui == "failure") || (stored == "failure" && ui == "success")
  end

  def report_results
    puts "\n" + "=" * 60
    puts "VERIFICATION RESULTS"
    puts "=" * 60

    if @discrepancies.empty?
      puts "✓ All verified PRs match between API and UI"
    else
      puts "⚠️  Found #{@discrepancies.length} discrepancies:"
      @discrepancies.each do |d|
        puts "\n  PR ##{d[:pr_number]}: #{d[:pr_url]}"
        puts "    Stored: ci_status=#{d[:stored][:ci_status]}, failed=#{d[:stored][:failed_checks]}"
        puts "    UI:     ci_status=#{d[:ui][:status]}, failed=#{d[:ui][:failed]}"
      end
    end
  end

  def trigger_fix
    return unless @admin_token

    @discrepancies.each do |d|
      puts "Fixing PR ##{d[:pr_number]}..."
      response = HTTParty.get(
        "#{@api_url}/api/v1/admin/debug_pr",
        query: {
          token: @admin_token,
          pr_number: d[:pr_number],
          fix: true
        },
        timeout: 120
      )

      if response.success?
        puts "  ✓ Fixed"
      else
        puts "  ✗ Error: #{response.code}"
      end

      sleep 1
    end
  end
end

# Run verification
begin
  exit SeleniumCiVerifier.new.run(sample_size: 10)
rescue => e
  puts "FATAL ERROR: #{e.message}"
  puts e.backtrace.first(10).join("\n")
  exit 1
end

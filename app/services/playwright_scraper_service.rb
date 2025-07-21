require 'playwright'

class PlaywrightScraperService
  def initialize
    @logger = Logger.new(STDOUT)
  end

  def scrape_pr_checks_detailed(pr_url)
    start_time = Time.now
    result = {
      overall_status: 'unknown',
      total_checks: 0,
      successful_checks: 0,
      failed_checks: 0,
      pending_checks: 0,
      checks: []
    }

    Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
      browser = playwright.chromium.launch(
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox']
      )
      
      begin
        context = browser.new_context(
          viewport: { width: 1920, height: 1080 },
          user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        )
        
        page = context.new_page
        
        # Navigate to PR page
        @logger.info "Navigating to: #{pr_url}"
        page.goto(pr_url, wait_until: 'networkidle', timeout: 30000)
        
        # Wait for checks to load - multiple strategies
        begin
          # First try: Wait for the checks summary element
          page.wait_for_selector('[data-testid="checks-status-badge"]', timeout: 10000)
        rescue
          # Fallback: Wait for merge box or status checks
          begin
            page.wait_for_selector('.merge-status-list', timeout: 5000)
          rescue
            # Last resort: Just wait for network idle
            page.wait_for_load_state('networkidle')
          end
        end
        
        # Additional wait to ensure dynamic content loads
        page.wait_for_timeout(2000)
        
        # Try multiple selectors to find check information
        checks_data = extract_checks_data(page)
        
        # Parse the checks
        if checks_data[:checks].any?
          result[:checks] = checks_data[:checks]
          result[:total_checks] = checks_data[:total]
          result[:successful_checks] = checks_data[:successful]
          result[:failed_checks] = checks_data[:failed]
          result[:pending_checks] = checks_data[:pending]
          
          # Determine overall status
          if checks_data[:failed] > 0
            result[:overall_status] = 'failure'
          elsif checks_data[:pending] > 0
            result[:overall_status] = 'pending'
          elsif checks_data[:successful] > 0
            result[:overall_status] = 'success'
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

    # Strategy 1: Try to find GitHub's check runs list
    check_runs = page.locator('[data-testid="check-run-item"], .merge-status-item, .status-check-rollup-item').all
    
    if check_runs.any?
      @logger.info "Found #{check_runs.length} check items using test-id selectors"
      
      check_runs.each do |check_element|
        begin
          # Extract check details
          name = check_element.locator('.status-check-item-name, [data-testid="check-run-name"], .merge-status-item-name').first&.text_content&.strip
          next unless name
          
          # Determine status from various indicators
          status = determine_check_status(check_element)
          
          checks << {
            name: name,
            status: status,
            required: check_element.text_content.include?('Required') || false
          }
          
          # Count statuses
          case status
          when 'success' then successful += 1
          when 'failure', 'error' then failed += 1
          when 'pending', 'in_progress' then pending += 1
          end
          
          total += 1
        rescue => e
          @logger.warn "Error parsing check element: #{e.message}"
        end
      end
    end
    
    # Strategy 2: If no individual checks found, try summary counts
    if checks.empty?
      summary_text = page.locator('.branch-action-item-summary, .merge-status-list-summary').first&.text_content
      if summary_text
        @logger.info "Using summary text: #{summary_text}"
        
        # Parse summary like "18 successful checks"
        if summary_text =~ /(\d+)\s+successful/
          successful = $1.to_i
          total += successful
        end
        if summary_text =~ /(\d+)\s+failing/
          failed = $1.to_i
          total += failed
        end
        if summary_text =~ /(\d+)\s+pending/
          pending = $1.to_i
          total += pending
        end
        
        # Create placeholder checks
        total.times do |i|
          status = if i < successful
            'success'
          elsif i < successful + failed
            'failure'
          else
            'pending'
          end
          
          checks << {
            name: "Check #{i + 1}",
            status: status,
            required: false
          }
        end
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

  def determine_check_status(element)
    text = element.text_content.downcase
    
    # Check for status indicators in order of precedence
    return 'failure' if text.include?('failed') || text.include?('failure') || element.locator('.octicon-x').count > 0
    return 'success' if text.include?('successful') || text.include?('passed') || element.locator('.octicon-check').count > 0
    return 'pending' if text.include?('pending') || text.include?('queued') || element.locator('.octicon-dot-fill').count > 0
    return 'in_progress' if text.include?('in progress') || text.include?('running')
    
    'unknown'
  end
end
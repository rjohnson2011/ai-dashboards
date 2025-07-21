require 'playwright'

class AuthenticatedPlaywrightScraperService
  def initialize
    @logger = Logger.new(STDOUT)
    @github_token = ENV['GITHUB_TOKEN']
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
      browser = playwright.chromium.launch(headless: false) # Set to false for debugging
      
      begin
        context = browser.new_context
        
        # Add GitHub authentication token as a cookie
        if @github_token
          context.add_cookies([{
            name: 'logged_in',
            value: 'yes',
            domain: 'github.com',
            path: '/'
          }])
          
          # Set authorization header
          context.set_extra_http_headers({
            'Authorization' => "token #{@github_token}"
          })
        end
        
        page = context.new_page
        
        # Navigate to PR page
        @logger.info "Navigating to: #{pr_url}"
        page.goto(pr_url)
        
        # Wait for the page to load
        page.wait_for_load_state
        
        # Take a screenshot for debugging
        page.screenshot(path: 'pr_page_screenshot.png')
        @logger.info "Screenshot saved to pr_page_screenshot.png"
        
        # Wait longer for dynamic content
        sleep 5
        
        # Try to find the merge box which contains check information
        merge_box = page.query_selector('.merge-status-list, .branch-action-details, [data-testid="pr-merge-section"]')
        
        if merge_box
          @logger.info "Found merge box, extracting check information..."
          
          # Get all text from the merge area
          merge_text = merge_box.text_content
          @logger.info "Merge box text: #{merge_text[0..200]}..."
          
          # Look for check count patterns
          if merge_text =~ /(\d+)\s+checks?\s+pass/i || merge_text =~ /(\d+)\s+successful/i
            result[:successful_checks] = $1.to_i
          end
          
          if merge_text =~ /(\d+)\s+checks?\s+fail/i || merge_text =~ /(\d+)\s+failing/i
            result[:failed_checks] = $1.to_i
          end
          
          if merge_text =~ /(\d+)\s+pending/i || merge_text =~ /(\d+)\s+in\s+progress/i
            result[:pending_checks] = $1.to_i
          end
          
          # Look for specific check items
          check_items = page.query_selector_all('.merge-status-item, .status-check-item, [data-testid*="check"]')
          
          @logger.info "Found #{check_items.length} check items"
          
          check_items.each do |item|
            text = item.text_content.strip
            next if text.empty?
            
            name = text.split("\n").first
            status = 'unknown'
            
            # Check for status indicators
            if item.query_selector('.octicon-check, .text-green, [aria-label*="success"]')
              status = 'success'
            elsif item.query_selector('.octicon-x, .text-red, [aria-label*="fail"]')
              status = 'failure'
            elsif item.query_selector('.octicon-dot-fill, .text-yellow, [aria-label*="pending"]')
              status = 'pending'
            end
            
            result[:checks] << {
              name: name,
              status: status,
              required: text.downcase.include?('required')
            }
          end
        else
          @logger.warn "Could not find merge box - page might require authentication"
          
          # Try alternative selectors
          alt_text = page.text_content
          if alt_text.include?("Sign in to view")
            @logger.error "Page requires authentication - GitHub token might not be working"
          end
        end
        
        # Calculate totals
        if result[:checks].any?
          result[:total_checks] = result[:checks].length
          result[:successful_checks] = result[:checks].count { |c| c[:status] == 'success' }
          result[:failed_checks] = result[:checks].count { |c| c[:status] == 'failure' }
          result[:pending_checks] = result[:checks].count { |c| c[:status] == 'pending' }
        else
          # Use counts from text parsing
          result[:total_checks] = result[:successful_checks] + result[:failed_checks] + result[:pending_checks]
        end
        
        # Determine overall status
        if result[:failed_checks] > 0
          result[:overall_status] = 'failure'
        elsif result[:pending_checks] > 0
          result[:overall_status] = 'pending'
        elsif result[:successful_checks] > 0
          result[:overall_status] = 'success'
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
end
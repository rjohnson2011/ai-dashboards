require 'httparty'
require 'nokogiri'

class EnhancedGithubScraperService
  include HTTParty
  
  def initialize
    @base_url = "https://github.com"
    self.class.headers 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
  end
  
  def scrape_pr_checks_detailed(pr_url)
    begin
      # Extract PR number and repo from URL
      if match = pr_url.match(/github\.com\/([^\/]+\/[^\/]+)\/pull\/(\d+)/)
        repo = match[1]
        pr_number = match[2].to_i
      else
        Rails.logger.error "Could not parse PR URL: #{pr_url}"
        return fallback_to_pr_page(pr_url)
      end
      
      # Get check counts from GitHub API if available
      api_counts = get_api_check_counts(repo, pr_number)
      
      # Get the checks page for details
      checks_url = pr_url + '/checks'
      response = self.class.get(checks_url)
      
      if response.code != 200
        Rails.logger.error "Failed to fetch PR checks page: #{response.code}"
        # If we have API counts, use those
        if api_counts
          return {
            overall_status: api_counts[:overall_status],
            checks: [],
            total_checks: api_counts[:total],
            successful_checks: api_counts[:successful],
            failed_checks: api_counts[:failed]
          }
        end
        return fallback_to_pr_page(pr_url)
      end
      
      doc = Nokogiri::HTML(response.body)
      
      # First try to get the summary counts from the page
      summary_counts = extract_summary_counts(doc)
      
      # Extract individual checks for details
      checks = extract_checks_from_page(doc)
      
      # If no checks found and no summary, fallback to PR page
      if checks.empty? && !summary_counts
        Rails.logger.info "No checks or summary found, falling back to PR page"
        return fallback_to_pr_page(pr_url)
      end
      
      # Deduplicate checks by suite name
      unique_checks = deduplicate_checks(checks)
      
      # Always prefer API counts if available
      if api_counts
        Rails.logger.info "Using API counts: #{api_counts[:failed]} failing, #{api_counts[:successful]} successful (#{api_counts[:total]} total)"
        overall_status = api_counts[:overall_status]
        total = api_counts[:total]
        successful = api_counts[:successful]
        failed = api_counts[:failed]
        
        # If we have more detailed check information, use it for the checks array
        # but keep the API counts for the totals
        if unique_checks.empty? && total > 0
          # Create a placeholder check entry if we don't have individual checks
          unique_checks = [{
            name: "GitHub Checks",
            status: overall_status,
            url: checks_url,
            description: "#{failed} failing, #{successful} successful checks",
            required: true,
            suite_name: "All Checks"
          }]
        end
      else
        # Otherwise, calculate from individual checks
        Rails.logger.info "No API counts, calculating from #{unique_checks.count} individual checks"
        overall_status = determine_overall_status(unique_checks)
        total = unique_checks.count
        successful = unique_checks.count { |c| c[:status] == 'success' }
        failed = unique_checks.count { |c| ['failure', 'error', 'cancelled'].include?(c[:status]) }
      end
      
      {
        overall_status: overall_status,
        checks: unique_checks,
        total_checks: total,
        successful_checks: successful,
        failed_checks: failed
      }
      
    rescue => e
      Rails.logger.error "Error scraping PR checks: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      fallback_to_pr_page(pr_url)
    end
  end
  
  private
  
  def get_api_check_counts(repo, pr_number)
    # Use GitHub API to get accurate check counts
    # This method should be implemented to use the GitHub service
    # For now, return nil to use scraping
    begin
      github_service = GithubService.new
      
      # Get PR to find head SHA
      pr = github_service.all_pull_requests(state: 'open').find { |p| p.number == pr_number }
      return nil unless pr
      
      client = github_service.instance_variable_get(:@client)
      
      # Get check runs
      check_runs = client.check_runs_for_ref(repo, pr.head.sha)
      check_run_successful = check_runs.check_runs.count { |r| r.conclusion == 'success' }
      check_run_failed = check_runs.check_runs.count { |r| ['failure', 'cancelled', 'timed_out'].include?(r.conclusion) }
      
      # Get commit statuses
      combined_status = github_service.commit_status(pr.head.sha)
      status_successful = 0
      status_failed = 0
      
      if combined_status && combined_status.statuses.any?
        # Get unique statuses (latest for each context)
        unique_statuses = combined_status.statuses.uniq { |s| s.context }
        status_successful = unique_statuses.count { |s| s.state == 'success' }
        status_failed = unique_statuses.count { |s| ['failure', 'error'].include?(s.state) }
      end
      
      # Combine both
      total_successful = check_run_successful + status_successful
      total_failed = check_run_failed + status_failed
      total = check_runs.total_count + (combined_status ? combined_status.statuses.uniq { |s| s.context }.count : 0)
      
      overall_status = total_failed > 0 ? 'failure' : 'success'
      
      Rails.logger.info "API counts - Check runs: #{check_runs.total_count}, Commit statuses: #{combined_status&.statuses&.uniq { |s| s.context }&.count || 0}"
      Rails.logger.info "API totals - Total: #{total}, Successful: #{total_successful}, Failed: #{total_failed}"
      
      {
        total: total,
        successful: total_successful,
        failed: total_failed,
        overall_status: overall_status
      }
    rescue => e
      Rails.logger.error "Error getting API check counts: #{e.message}"
      nil
    end
  end
  
  def extract_summary_counts(doc)
    # Look for the summary text like "1 failing, 23 successful checks"
    # This text appears in the fgColor-muted class element below the MergeBoxSectionHeader
    
    # Look for the specific class that contains the summary
    summary_elements = doc.css('.fgColor-muted')
    summary_elements.each do |elem|
      elem_text = elem.text.strip
      
      # Pattern for mixed results: "X failing, Y successful checks"
      if match = elem_text.match(/(\d+)\s+failing,\s+(\d+)\s+successful\s+checks?/i)
        failed = match[1].to_i
        successful = match[2].to_i
        Rails.logger.info "Found summary in .fgColor-muted: #{failed} failing, #{successful} successful"
        return {
          failed: failed,
          successful: successful,
          total: failed + successful,
          overall_status: 'failure'
        }
      end
      
      # Pattern for all successful: "X successful checks"
      if match = elem_text.match(/^(\d+)\s+successful\s+checks?$/i)
        successful = match[1].to_i
        Rails.logger.info "Found all successful: #{successful} checks"
        return {
          failed: 0,
          successful: successful,
          total: successful,
          overall_status: 'success'
        }
      end
      
      # Pattern for pending: "X pending, Y successful checks"
      if match = elem_text.match(/(\d+)\s+pending,\s+(\d+)\s+successful\s+checks?/i)
        pending = match[1].to_i
        successful = match[2].to_i
        Rails.logger.info "Found pending: #{pending} pending, #{successful} successful"
        return {
          failed: 0,
          successful: successful,
          pending: pending,
          total: pending + successful,
          overall_status: 'pending'
        }
      end
      
      # Pattern for mixed with pending: "X failing, Y pending, Z successful checks"
      if match = elem_text.match(/(\d+)\s+failing,\s+(\d+)\s+pending,\s+(\d+)\s+successful\s+checks?/i)
        failed = match[1].to_i
        pending = match[2].to_i
        successful = match[3].to_i
        Rails.logger.info "Found mixed: #{failed} failing, #{pending} pending, #{successful} successful"
        return {
          failed: failed,
          successful: successful,
          pending: pending,
          total: failed + pending + successful,
          overall_status: 'failure'
        }
      end
      
      # Pattern for expected: "X expected, Y successful checks"
      if match = elem_text.match(/(\d+)\s+expected,\s+(\d+)\s+successful\s+checks?/i)
        expected = match[1].to_i
        successful = match[2].to_i
        Rails.logger.info "Found expected: #{expected} expected, #{successful} successful"
        return {
          failed: 0,
          successful: successful,
          pending: expected,
          total: expected + successful,
          overall_status: 'pending'
        }
      end
      
      # Pattern for complex: "X failing, Y skipped, Z expected, W successful checks"
      if match = elem_text.match(/(\d+)\s+failing,\s+(\d+)\s+skipped,\s+(\d+)\s+expected,\s+(\d+)\s+successful\s+checks?/i)
        failed = match[1].to_i
        skipped = match[2].to_i
        expected = match[3].to_i
        successful = match[4].to_i
        total = failed + skipped + expected + successful
        Rails.logger.info "Found complex: #{failed} failing, #{skipped} skipped, #{expected} expected, #{successful} successful"
        return {
          failed: failed,
          successful: successful,
          pending: expected,
          skipped: skipped,
          total: total,
          overall_status: 'failure'
        }
      end
      
      # Pattern for failing + skipped: "X failing, Y skipped, Z successful checks"
      if match = elem_text.match(/(\d+)\s+failing,\s+(\d+)\s+skipped,\s+(\d+)\s+successful\s+checks?/i)
        failed = match[1].to_i
        skipped = match[2].to_i
        successful = match[3].to_i
        total = failed + skipped + successful
        Rails.logger.info "Found with skipped: #{failed} failing, #{skipped} skipped, #{successful} successful"
        return {
          failed: failed,
          successful: successful,
          skipped: skipped,
          total: total,
          overall_status: 'failure'
        }
      end
    end
    
    # Fallback to checking in merge box section area
    merge_box_elements = doc.css('.mb-0.fgColor-muted, .MergeBoxSectionHeader-module__MergeBoxSectionHeading--gS3rL + *')
    merge_box_elements.each do |elem|
      elem_text = elem.text.strip
      
      if match = elem_text.match(/(\d+)\s+failing,\s+(\d+)\s+successful\s+checks?/i)
        failed = match[1].to_i
        successful = match[2].to_i
        Rails.logger.info "Found summary in merge box area: #{failed} failing, #{successful} successful"
        return {
          failed: failed,
          successful: successful,
          total: failed + successful,
          overall_status: 'failure'
        }
      end
    end
    
    Rails.logger.warn "No summary counts found on page. Searched .fgColor-muted and merge box elements."
    nil # No summary found
  end
  
  def extract_checks_from_page(doc)
    checks = []
    
    # Look for individual check items, excluding suite headers
    # Suite headers typically have different structure and don't have status icons
    check_items = doc.css('.checks-list-item')
    
    check_items.each do |item|
      # Skip if this is a suite header (usually doesn't have octicon status icons)
      next if is_suite_header?(item)
      
      check_data = extract_check_data(item)
      # Include checks even with 'unknown' status if they have a name
      checks << check_data if check_data[:name] && check_data[:status]
    end
    
    checks
  end
  
  def is_suite_header?(element)
    # Suite headers typically:
    # 1. Have expandable/collapsible structure
    # 2. Don't have direct status indicators
    # 3. Have a different DOM structure
    
    # Check if it has expand/collapse indicators
    has_expand_indicator = element.css('.octicon-chevron-right, .octicon-chevron-down').any?
    
    # Check for suite-specific classes
    element_classes = element.attr('class').to_s
    is_parent_item = element_classes.include?('expandable') || 
                     element_classes.include?('group-header') ||
                     element_classes.include?('suite-header') ||
                     element.css('.checks-list-item-group').any?
    
    # Check if the name matches known suite patterns
    name_text = element.text.strip
    is_suite_name = name_text.match?(/^(Build And Publish|Code Checks|PR Labeler|Pull Request Ready|Validate DataDog|Check CODEOWNERS|Warn PR|CodeQL|Danger)\s*$/i)
    
    # It's a suite if it has expand indicator or matches suite patterns
    has_expand_indicator || is_parent_item || is_suite_name
  end
  
  def extract_check_data(element)
    name = extract_check_name(element)
    status = extract_check_status(element)
    url = extract_check_url(element)
    description = extract_check_description(element)
    required = extract_required_status(element)
    suite_name = extract_suite_name(name)
    
    {
      name: name,
      status: status,
      url: url,
      description: description,
      required: required,
      suite_name: suite_name
    }
  end
  
  def extract_check_name(element)
    # Try different selectors to find the check name
    name_selectors = [
      '.checks-list-item-name .css-truncate-target',
      '.checks-list-item-name span',
      '.status-meta strong',
      'strong'
    ]
    
    name_selectors.each do |selector|
      name_element = element.css(selector).first
      if name_element
        name = name_element.text.strip
        return name unless name.empty?
      end
    end
    
    # Fallback to element text
    text = element.text.strip
    lines = text.split("\n").map(&:strip).reject(&:empty?)
    return lines.first if lines.any?
    
    nil
  end
  
  def extract_check_status(element)
    # Check for GitHub's specific status icons first (most reliable)
    if element.css('.octicon-check, .octicon-check-circle, .octicon-check-circle-fill').any?
      return 'success'
    elsif element.css('.octicon-x, .octicon-x-circle, .octicon-x-circle-fill').any?
      return 'failure'
    elsif element.css('.octicon-dot, .octicon-dot-fill, .octicon-primitive-dot').any?
      return 'pending'
    elsif element.css('.octicon-skip, .octicon-dash').any?
      return 'skipped'
    end
    
    # Check for status in aria-label attributes
    aria_labels = element.css('[aria-label]').map { |e| e.attr('aria-label').to_s.downcase }
    aria_labels.each do |label|
      return 'success' if label.include?('success') || label.include?('passed')
      return 'failure' if label.include?('fail') || label.include?('error')
      return 'pending' if label.include?('pending') || label.include?('progress') || label.include?('waiting')
      return 'skipped' if label.include?('skip') || label.include?('neutral')
    end
    
    # Check for color-based status indicators
    element_html = element.to_s
    if element_html.include?('color-fg-success') || element_html.include?('color-bg-success')
      return 'success'
    elsif element_html.include?('color-fg-danger') || element_html.include?('color-bg-danger')
      return 'failure'
    elsif element_html.include?('color-fg-attention') || element_html.include?('color-bg-attention')
      return 'pending'
    elsif element_html.include?('color-fg-subtle') || element_html.include?('neutral')
      return 'skipped'
    end
    
    # Check text content for status indicators
    text = element.text.downcase
    return 'success' if text.include?('success') || text.include?('passed') || text.include?('succeeded')
    return 'failure' if text.include?('failed') || text.include?('failure') || text.include?('error')
    return 'pending' if text.include?('pending') || text.include?('in progress') || text.include?('running') || text.include?('waiting')
    return 'skipped' if text.include?('skipped') || text.include?('skip') || text.include?('neutral')
    
    'unknown'
  end
  
  def extract_check_url(element)
    link = element.css('a[href]').first
    if link
      href = link.attr('href')
      return href.start_with?('http') ? href : @base_url + href
    end
    nil
  end
  
  def extract_check_description(element)
    # Look for descriptive text
    text = element.text.strip
    lines = text.split("\n").map(&:strip).reject(&:empty?)
    
    # Return the second line if it exists and looks like a description
    if lines.length > 1 && lines[1].length > 10
      return lines[1]
    end
    
    nil
  end
  
  def extract_required_status(element)
    text = element.text.downcase
    text.include?('required') || text.include?('Required')
  end
  
  def extract_suite_name(name)
    return nil unless name
    
    # Extract suite name from patterns like "Suite Name / Check Name"
    if name.include?(' / ')
      return name.split(' / ').first
    end
    
    # For other patterns, use the first few words
    words = name.split
    if words.length > 3
      return words[0..2].join(' ')
    end
    
    name
  end
  
  def deduplicate_checks(checks)
    # Group by suite name and keep the most relevant check per suite
    grouped = checks.group_by { |check| check[:suite_name] }
    
    grouped.map do |suite, suite_checks|
      # Prefer required checks, then failed checks, then successful checks
      priority_check = suite_checks.sort_by do |check|
        priority = 0
        priority += 1000 if check[:required]
        priority += 100 if ['failure', 'error'].include?(check[:status])
        priority += 10 if check[:status] == 'success'
        -priority # Negative to sort in descending order
      end.first
      
      priority_check
    end
  end
  
  def determine_overall_status(checks)
    return 'unknown' if checks.empty?
    
    required_checks = checks.select { |c| c[:required] }
    
    # If there are required checks, use them to determine status
    if required_checks.any?
      failed_required = required_checks.select { |c| ['failure', 'error', 'cancelled'].include?(c[:status]) }
      return 'failure' if failed_required.any?
      
      # If all required checks are successful, overall status is success
      successful_required = required_checks.select { |c| c[:status] == 'success' }
      return 'success' if successful_required.count == required_checks.count
      
      # If there are pending required checks, status is pending
      return 'pending'
    end
    
    # If no required checks, use overall check status
    failed_checks = checks.select { |c| ['failure', 'error', 'cancelled'].include?(c[:status]) }
    return 'failure' if failed_checks.any?
    
    successful_checks = checks.select { |c| c[:status] == 'success' }
    return 'success' if successful_checks.any?
    
    'pending'
  end
  
  def fallback_to_pr_page(pr_url)
    pr_response = self.class.get(pr_url)
    if pr_response.code == 200
      pr_doc = Nokogiri::HTML(pr_response.body)
      
      # Look for overall status indicator
      overall_status_element = pr_doc.css('.checks-summary-conclusion').first
      if overall_status_element
        status_class = overall_status_element.attr('class')
        if status_class.include?('color-bg-success')
          overall_status = 'success'
        elsif status_class.include?('color-bg-danger')
          overall_status = 'failure'
        elsif status_class.include?('color-bg-attention')
          overall_status = 'pending'
        else
          overall_status = 'unknown'
        end
        
        # Get check count from tab
        checks_tab = pr_doc.css('a[href*="/checks"] .Counter').first
        checks_count = checks_tab ? checks_tab.text.strip.to_i : 0
        
        return {
          overall_status: overall_status,
          checks: [{
            name: "All Checks",
            status: overall_status,
            url: pr_url + '/checks',
            description: "#{checks_count} checks with overall status: #{overall_status}",
            required: false,
            suite_name: "All Checks"
          }],
          total_checks: 1,
          successful_checks: overall_status == 'success' ? 1 : 0,
          failed_checks: overall_status == 'failure' ? 1 : 0
        }
      end
    end
    
    # Ultimate fallback
    {
      overall_status: 'unknown',
      checks: [],
      total_checks: 0,
      successful_checks: 0,
      failed_checks: 0
    }
  end
end
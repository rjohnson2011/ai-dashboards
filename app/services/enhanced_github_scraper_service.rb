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
      # Get the PR checks page
      checks_url = pr_url + '/checks'
      response = self.class.get(checks_url)
      
      if response.code != 200
        Rails.logger.error "Failed to fetch PR checks page: #{response.code}"
        return fallback_to_pr_page(pr_url)
      end
      
      doc = Nokogiri::HTML(response.body)
      
      # Extract checks from the checks page
      checks = extract_checks_from_page(doc)
      
      # If no checks found, fallback to PR page
      if checks.empty?
        return fallback_to_pr_page(pr_url)
      end
      
      # Deduplicate checks by suite name
      unique_checks = deduplicate_checks(checks)
      
      # Determine overall status based on required checks
      overall_status = determine_overall_status(unique_checks)
      
      {
        overall_status: overall_status,
        checks: unique_checks,
        total_checks: unique_checks.count,
        successful_checks: unique_checks.count { |c| c[:status] == 'success' },
        failed_checks: unique_checks.count { |c| ['failure', 'error', 'cancelled'].include?(c[:status]) }
      }
      
    rescue => e
      Rails.logger.error "Error scraping PR checks: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      fallback_to_pr_page(pr_url)
    end
  end
  
  private
  
  def extract_checks_from_page(doc)
    checks = []
    
    # Look for individual check items
    check_items = doc.css('.checks-list-item')
    
    check_items.each do |item|
      check_data = extract_check_data(item)
      checks << check_data if check_data[:name] && check_data[:status]
    end
    
    checks
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
    # Check for GitHub's specific status icons first
    if element.css('.octicon-check').any?
      return 'success'
    elsif element.css('.octicon-x').any?
      return 'failure'
    elsif element.css('.octicon-primitive-dot').any?
      return 'pending'
    end
    
    # Check for color-based status indicators
    classes = element.attr('class').to_s.downcase
    if classes.include?('color-fg-success') || element.css('.color-fg-success').any?
      return 'success'
    elsif classes.include?('color-fg-danger') || element.css('.color-fg-danger').any?
      return 'failure'
    elsif classes.include?('color-fg-attention') || element.css('.color-fg-attention').any?
      return 'pending'
    end
    
    # Check text content for status indicators
    text = element.text.downcase
    return 'success' if text.include?('success') || text.include?('passed') || text.include?('succeeded')
    return 'failure' if text.include?('failed') || text.include?('failure') || text.include?('error')
    return 'pending' if text.include?('pending') || text.include?('in progress') || text.include?('running')
    return 'skipped' if text.include?('skipped') || text.include?('skip')
    
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
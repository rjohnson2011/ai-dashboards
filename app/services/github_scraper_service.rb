require 'httparty'
require 'nokogiri'

class GithubScraperService
  include HTTParty
  
  def initialize
    @base_url = "https://github.com"
    # Add User-Agent to avoid being blocked
    self.class.headers 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
  end
  
  def scrape_pr_checks(pr_url)
    begin
      # Get the PR checks page instead of the main PR page
      checks_url = pr_url + '/checks'
      response = self.class.get(checks_url)
      
      if response.code != 200
        Rails.logger.error "Failed to fetch PR checks page: #{response.code}"
        return default_response
      end
      
      doc = Nokogiri::HTML(response.body)
      
      # Look for checks in the GitHub checks page
      checks = []
      
      # New GitHub checks page structure
      check_selectors = [
        '.checks-list-item',
        '.check-run-item',
        '.status-check-item'
      ]
      
      check_selectors.each do |selector|
        found_checks = doc.css(selector)
        
        found_checks.each do |check_element|
          check_name = extract_check_name(check_element)
          check_status = extract_check_status(check_element)
          check_url = extract_check_url(check_element)
          
          if check_name && check_status
            checks << {
              name: check_name,
              status: check_status,
              url: check_url,
              description: extract_check_description(check_element)
            }
          end
        end
        
        # If we found checks, break out of the loop
        break if checks.any?
      end
      
      # If no checks found on checks page, try the main PR page
      if checks.empty?
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
            
            checks << {
              name: "All Checks (#{checks_count})",
              status: overall_status,
              url: pr_url + '/checks',
              description: "#{checks_count} checks with overall status: #{overall_status}"
            }
          end
        end
      end
      
      # Fallback: try to find the checks tab and count
      if checks.empty?
        pr_response = self.class.get(pr_url)
        if pr_response.code == 200
          pr_doc = Nokogiri::HTML(pr_response.body)
          checks_tab = pr_doc.css('a[href*="/checks"]').first
          if checks_tab
            checks_text = checks_tab.text.strip
            if checks_text.match(/(\d+)/)
              checks_count = checks_text.match(/(\d+)/)[1].to_i
              
              # If there are checks but we can't parse them, return generic info
              if checks_count > 0
                checks << {
                  name: "Checks (#{checks_count})",
                  status: 'unknown',
                  url: pr_url + '/checks',
                  description: "#{checks_count} checks found but details not accessible"
                }
              end
            end
          end
        end
      end
      
      # Remove duplicates and normalize check names
      unique_checks = deduplicate_checks(checks)
      
      # Determine overall status
      overall_status = determine_overall_status(unique_checks)
      failing_checks = unique_checks.select { |c| ['failure', 'error', 'cancelled'].include?(c[:status]) }
      
      {
        overall_status: overall_status,
        failing_checks: failing_checks,
        all_checks: unique_checks,
        total_checks: unique_checks.count
      }
      
    rescue => e
      Rails.logger.error "Error scraping PR checks: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      default_response
    end
  end
  
  private
  
  def extract_check_name(element)
    # Try different selectors to find the check name
    name_selectors = [
      '.checks-list-item-name .css-truncate-target',
      '.checks-list-item-name span',
      '.status-meta strong',
      '.merge-status-item strong',
      '.status-actions strong',
      '.text-emphasized',
      '.h4',
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
    return text.split(/\s+/).first(3).join(' ') if text.length > 0
    
    nil
  end
  
  def extract_check_status(element)
    # Look for status indicators in classes and text
    classes = element.attr('class').to_s.downcase
    text = element.text.downcase
    
    # Check for GitHub's specific status icons first
    if element.css('.octicon-check').any?
      return 'success'
    elsif element.css('.octicon-x').any?
      return 'failure'
    elsif element.css('.octicon-primitive-dot').any?
      return 'pending'
    end
    
    # Check for color-based status indicators
    if classes.include?('color-fg-success') || element.css('.color-fg-success').any?
      return 'success'
    elsif classes.include?('color-fg-danger') || element.css('.color-fg-danger').any?
      return 'failure'
    elsif classes.include?('color-fg-attention') || element.css('.color-fg-attention').any?
      return 'pending'
    end
    
    # Check classes for status indicators
    return 'success' if classes.include?('success') || classes.include?('passed')
    return 'failure' if classes.include?('failure') || classes.include?('failed') || classes.include?('error')
    return 'pending' if classes.include?('pending') || classes.include?('in-progress')
    
    # Check text content for status indicators
    return 'success' if text.include?('success') || text.include?('passed') || text.include?('✓') || text.include?('succeeded')
    return 'failure' if text.include?('failed') || text.include?('failure') || text.include?('error') || text.include?('✗')
    return 'pending' if text.include?('pending') || text.include?('in progress') || text.include?('running')
    
    'unknown'
  end
  
  def extract_check_url(element)
    # Look for links within the check element
    link = element.css('a[href]').first
    if link
      href = link.attr('href')
      return href.start_with?('http') ? href : @base_url + href
    end
    
    nil
  end
  
  def extract_check_description(element)
    # Try to find descriptive text
    desc_selectors = [
      '.status-meta .text-small',
      '.merge-status-item .text-small',
      '.text-gray'
    ]
    
    desc_selectors.each do |selector|
      desc_element = element.css(selector).first
      if desc_element
        desc = desc_element.text.strip
        return desc unless desc.empty?
      end
    end
    
    nil
  end
  
  def determine_overall_status(checks)
    return 'unknown' if checks.empty?
    
    statuses = checks.map { |c| c[:status] }
    
    return 'failure' if statuses.include?('failure') || statuses.include?('error')
    return 'pending' if statuses.include?('pending')
    return 'success' if statuses.all? { |s| s == 'success' }
    
    'unknown'
  end
  
  def deduplicate_checks(checks)
    # Group checks by normalized name and keep the most informative one
    grouped_checks = {}
    
    checks.each do |check|
      # Normalize the check name by removing redundant parts
      normalized_name = normalize_check_name(check[:name])
      
      # If we haven't seen this check before, keep it
      if !grouped_checks[normalized_name]
        grouped_checks[normalized_name] = check.merge(name: normalized_name)
      else
        # If we have seen it, prefer the one with failure status (more important)
        existing_check = grouped_checks[normalized_name]
        if check[:status] == 'failure' && existing_check[:status] != 'failure'
          grouped_checks[normalized_name] = check.merge(name: normalized_name)
        elsif check[:status] == existing_check[:status] && 
              check[:description].to_s.length > existing_check[:description].to_s.length
          # If same status, prefer the one with more description
          grouped_checks[normalized_name] = check.merge(name: normalized_name)
        end
      end
    end
    
    grouped_checks.values
  end
  
  def normalize_check_name(name)
    return name unless name
    
    # Handle specific patterns we see in GitHub that create duplicates
    case name
    when /^Require backend-review-group approval.*Succeed if backend approval is confirmed/
      'Require backend-review-group approval'
    when /^.*\/\s*Succeed if backend approval is confirmed/
      'Require backend-review-group approval'
    when /Succeed if backend approval is confirmed/
      'Require backend-review-group approval'
    else
      # For other checks, keep the full name to preserve uniqueness
      name.strip
    end
  end

  def default_response
    {
      overall_status: 'unknown',
      failing_checks: [],
      all_checks: [],
      total_checks: 0
    }
  end
end
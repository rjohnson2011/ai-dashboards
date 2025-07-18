require 'httparty'
require 'nokogiri'

pr_url = "https://github.com/department-of-veterans-affairs/vets-api/pull/23158"

# Try the main PR page first
puts "Fetching main PR page..."
response = HTTParty.get(pr_url, headers: { 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' })

if response.code == 200
  doc = Nokogiri::HTML(response.body)
  
  # Save the HTML for inspection
  File.write('pr_checks_page.html', response.body)
  
  puts "Page saved to pr_checks_page.html"
  puts "\nSearching for summary text patterns...\n"
  
  # Search all text nodes
  text_nodes = doc.xpath('//*[not(self::script)][not(self::style)]/text()').map(&:text).map(&:strip).reject(&:empty?)
  
  # Look for any text containing numbers and "successful" or "failing"
  text_nodes.each do |text|
    if text.match(/\d+.*(?:successful|failing|unsuccessful|checks)/i)
      puts "Found potential match: #{text}"
    end
  end
  
  puts "\n\nSearching specific elements..."
  
  # Check various selectors
  selectors = [
    '.merge-status-item',
    '.merge-status-list', 
    '.branch-action-item',
    '.status-heading',
    '.merge-message',
    '.Box-row',
    '.checks-summary-conclusion',
    '[data-details-container]',
    '.Details-content--shown',
    '.merge-status-icon',
    '.text-normal'
  ]
  
  selectors.each do |selector|
    elements = doc.css(selector)
    if elements.any?
      puts "\n#{selector} (#{elements.count} found):"
      elements.each do |elem|
        text = elem.text.strip
        if text.length > 0 && text.length < 200
          puts "  - #{text}"
        end
      end
    end
  end
else
  puts "Failed to fetch page: #{response.code}"
end
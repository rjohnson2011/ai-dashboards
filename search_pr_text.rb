require 'httparty'
require 'nokogiri'

pr_url = "https://github.com/department-of-veterans-affairs/vets-api/pull/23158"

puts "Fetching PR page: #{pr_url}"
response = HTTParty.get(pr_url, headers: { 
  'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
  'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
})

if response.code == 200
  doc = Nokogiri::HTML(response.body)
  
  # Save for manual inspection
  File.write('pr_page.html', response.body)
  puts "Saved page to pr_page.html"
  
  # Look for any text mentioning checks
  puts "\n=== All text containing 'checks' ==="
  doc.css('*').each do |elem|
    text = elem.text.strip
    if text.match(/\d+.*checks/i) && text.length < 100 && !text.include?('workflow')
      puts "#{elem.name}: #{text}"
      puts "  Classes: #{elem.attr('class')}" if elem.attr('class')
      puts ""
    end
  end
  
  # Look for merge status area
  puts "\n=== Elements that might contain merge status ==="
  selectors = [
    '[class*="merge"]',
    '[class*="status"]',
    '[class*="check"]',
    '.branch-action-item',
    '.merge-status-item'
  ]
  
  selectors.each do |selector|
    elements = doc.css(selector)
    elements.each do |elem|
      text = elem.text.strip
      if text.match(/\d+/) && text.length < 150
        puts "#{selector}: #{text}"
      end
    end
  end
else
  puts "Failed to fetch page: #{response.code}"
end
require 'httparty'
require 'nokogiri'

url = "https://github.com/department-of-veterans-affairs/vets-api/pull/23012/checks"
response = HTTParty.get(url, headers: { 'User-Agent' => 'Mozilla/5.0' })

doc = Nokogiri::HTML(response.body)

# Look for summary text
puts "Looking for summary text..."
doc.css('.fgColor-muted').each do |elem|
  text = elem.text.strip
  if text.include?("failing") || text.include?("successful")
    puts "Found: '#{text}'"
  end
end

# Also check other possible locations
puts "\nChecking branch status areas..."
doc.css('.merge-status-list .completeness-indicator-success, .merge-status-list .completeness-indicator-error, .merge-status-list .completeness-indicator-pending').each do |elem|
  parent = elem.parent
  if parent
    text = parent.text.strip.gsub(/\s+/, ' ')
    puts "Found: '#{text}'"
  end
end

puts "\nChecking status summary..."
doc.css('[data-hovercard-type="check_suite"], [data-hovercard-type="check_run"]').each do |elem|
  parent = elem.parent
  if parent && parent.text.include?("checks")
    puts "Found: '#{parent.text.strip}'"
  end
end
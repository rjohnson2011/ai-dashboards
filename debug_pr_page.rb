require 'httparty'
require 'nokogiri'

pr_url = "https://github.com/department-of-veterans-affairs/vets-api/pull/23158"

puts "Fetching PR page: #{pr_url}"
response = HTTParty.get(pr_url, headers: { 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' })

if response.code == 200
  doc = Nokogiri::HTML(response.body)

  puts "\n=== Looking for .fgColor-muted elements ==="
  fgcolor_elements = doc.css('.fgColor-muted')
  puts "Found #{fgcolor_elements.count} .fgColor-muted elements"

  fgcolor_elements.each_with_index do |elem, idx|
    text = elem.text.strip
    if text.length > 0 && text.length < 200
      puts "\n[#{idx}] #{text}"

      # Check if this contains our pattern
      if text.match(/\d+.*(?:failing|successful|pending|checks)/i)
        puts "  ^^ THIS LOOKS LIKE OUR TARGET!"
      end
    end
  end

  puts "\n=== Looking for elements with 'mb-0' class ==="
  mb0_elements = doc.css('.mb-0')
  mb0_elements.each_with_index do |elem, idx|
    text = elem.text.strip
    if text.match(/\d+.*(?:failing|successful|pending|checks)/i)
      puts "\n[#{idx}] #{text}"
      puts "  Classes: #{elem.attr('class')}"
    end
  end

  puts "\n=== Searching for the exact text pattern anywhere ==="
  all_text = doc.text
  if match = all_text.match(/(\d+\s+failing,\s+\d+\s+successful\s+checks)/i)
    puts "Found exact pattern: #{match[0]}"

    # Try to find which element contains this
    doc.css('*').each do |elem|
      if elem.text.strip.include?(match[0])
        puts "  Found in element: <#{elem.name}> with classes: #{elem.attr('class')}"
        break
      end
    end
  else
    puts "Could not find the exact pattern '1 failing, 23 successful checks'"
  end
else
  puts "Failed to fetch page: #{response.code}"
end

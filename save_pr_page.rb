require 'httparty'

url = "https://github.com/department-of-veterans-affairs/vets-api/pull/23012"
response = HTTParty.get(url, headers: { 'User-Agent' => 'Mozilla/5.0' })

File.write("pr_23012.html", response.body)
puts "Saved PR page to pr_23012.html"
puts "Response code: #{response.code}"

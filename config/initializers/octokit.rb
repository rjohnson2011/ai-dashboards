Octokit.configure do |c|
  c.api_endpoint = ENV.fetch("GITHUB_API_ENDPOINT", "https://api.va.ghe.com")
  c.web_endpoint = ENV.fetch("GITHUB_WEB_ENDPOINT", "https://va.ghe.com")
end

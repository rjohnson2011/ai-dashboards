# Local Cron Job Setup (No Webhooks Needed)

Run the scraper from your local machine to avoid Render's IP rate limits.

## Setup

### 1. Create Local Sync Script
Create `local_sync.sh`:

```bash
#!/bin/bash
# local_sync.sh - Run from your machine to sync PR data

# Load environment variables
export GITHUB_TOKEN="your_github_pat"
export ADMIN_TOKEN="your_admin_token"
export API_URL="https://ai-dashboards.onrender.com"

# Run the sync
echo "[$(date)] Starting PR sync..."

# Call your API to trigger update
curl -X POST "$API_URL/api/v1/admin/update_full_data" \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"$ADMIN_TOKEN\"}" \
  > /tmp/pr_sync.log 2>&1

echo "[$(date)] Sync completed"
```

### 2. Set Up Cron Job
Add to your crontab (`crontab -e`):

```bash
# Run every 30 minutes during business hours (9 AM - 7 PM local time)
0,30 9-18 * * 1-5 /path/to/local_sync.sh >> /tmp/pr_sync_cron.log 2>&1
```

### 3. Or Use a Simple Background Script
Create `continuous_sync.rb`:

```ruby
#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'uri'

API_URL = 'https://ai-dashboards.onrender.com'
ADMIN_TOKEN = ENV['ADMIN_TOKEN']

def sync_prs
  uri = URI("#{API_URL}/api/v1/admin/update_full_data")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'
  request.body = { token: ADMIN_TOKEN }.to_json
  
  response = http.request(request)
  puts "[#{Time.now}] Sync response: #{response.code}"
rescue => e
  puts "[#{Time.now}] Error: #{e.message}"
end

# Run continuously
loop do
  sync_prs
  sleep(1800) # 30 minutes
end
```

Run it:
```bash
export ADMIN_TOKEN=your_token
nohup ruby continuous_sync.rb > sync.log 2>&1 &
```

## Benefits
- Uses YOUR IP address (no rate limits)
- No webhooks or organizational approval needed
- Can run on any machine with internet
- Simple and reliable
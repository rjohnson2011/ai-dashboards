# Fix GitHub Token Authentication in Render Cron Job

## The Issue

"401 - Bad credentials" means the token exists but is invalid. Common causes:

1. **Token format issues** (extra spaces, quotes)
2. **Token expired**
3. **Wrong token scope**
4. **Environment variable not syncing**

## Debugging Steps

### 1. Test Your Token Locally

```bash
# Test if your token works
curl -H "Authorization: token YOUR_GITHUB_TOKEN" https://api.github.com/rate_limit
```

Should return JSON with rate limit info, not an error.

### 2. Check Token Format in Render

In Render Dashboard → Cron Job → Environment:
- Make sure there are NO quotes around the token
- No extra spaces before/after
- Token should start with `ghp_` or `github_pat_`

❌ Wrong: `"ghp_abc123..."`
❌ Wrong: ` ghp_abc123... `
✅ Right: `ghp_abc123...`

### 3. Create a Fresh Token

If still failing, create a new token:
1. Go to https://github.com/settings/tokens/new
2. Name: `render-pr-scraper`
3. Expiration: 90 days (or longer)
4. Scopes: ✅ `repo` (full control)
5. Generate token
6. Copy immediately (you can't see it again)

### 4. Update Render Cron Job

1. Delete the old `GITHUB_TOKEN` variable
2. Add new one with fresh token
3. Save changes
4. Manually trigger job to test

## Alternative: Use Render Secrets

Instead of plain environment variables, use Render's secret files:

1. In Render Dashboard → Cron Job
2. Go to "Secret Files" tab
3. Add file:
   - Path: `/etc/secrets/github_token`
   - Contents: [your token]
4. Update script to read from file:

```ruby
# In github_service.rb
def initialize
  token = ENV['GITHUB_TOKEN'] || File.read('/etc/secrets/github_token').strip rescue nil
  @client = Octokit::Client.new(access_token: token)
end
```

## Temporary Workaround: Admin Endpoint

While fixing the token, you can trigger updates manually:

```bash
# From any machine with working GitHub token
export GITHUB_TOKEN=your_working_token
export ADMIN_TOKEN=your_admin_token

curl -X POST "https://ai-dashboards.onrender.com/api/v1/admin/update_full_data" \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"$ADMIN_TOKEN\"}"
```

## Verify Fix

After updating token, the cron job should show:
```
[2025-07-19 14:30:00] INFO: GitHub token present: Yes (40 chars)
[2025-07-19 14:30:01] INFO: GitHub API rate limit: 4999/5000
```

Not:
```
[2025-07-19 14:06:00] ERROR: Fatal error in cron job: GET https://api.github.com/rate_limit: 401 - Bad credentials
```

## If Still Failing

The cron job IS using different IPs now (good!), so if auth works, you won't hit rate limits. Focus on fixing the token authentication.
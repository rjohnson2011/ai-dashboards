# Create a GitHub Personal Access Token

## You're Using the Wrong Token!

A token starting with `sk` is NOT a GitHub token. You need a GitHub Personal Access Token.

## Step-by-Step: Create a GitHub Token

### 1. Go to GitHub Settings
https://github.com/settings/tokens/new

### 2. Create Classic Token (Recommended)
- **Note**: `Render PR Scraper`
- **Expiration**: 90 days (or custom)
- **Select scopes**:
  - ✅ `repo` (Full control of private repositories)
  - That's all you need!

### 3. Generate Token
- Click "Generate token"
- **COPY IT IMMEDIATELY** - You can't see it again!
- It will look like: `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### 4. Update Render Cron Job
1. Go to Render Dashboard → Your cron job
2. Environment → Edit `GITHUB_TOKEN`
3. Replace the `sk_xxx` token with your new `ghp_xxx` token
4. Save changes

### 5. Alternative: Fine-grained Token
If you prefer more limited access:
1. Go to https://github.com/settings/personal-access-tokens/new
2. Set expiration
3. Select repository: `department-of-veterans-affairs/vets-api`
4. Permissions:
   - Contents: Read
   - Pull requests: Read
   - Actions: Read (for checks)
5. Generate token (will start with `github_pat_`)

## Common Mistakes

❌ Using Slack token (`sk_xxx`)
❌ Using API key from another service
❌ Using GitHub OAuth app token
✅ Using GitHub Personal Access Token (`ghp_xxx` or `github_pat_xxx`)

## Test Your New Token

After updating in Render:
```bash
# Test locally first
export GITHUB_TOKEN=ghp_your_new_token_here
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/rate_limit
```

Should return:
```json
{
  "rate": {
    "limit": 5000,
    "remaining": 4999,
    ...
  }
}
```

## Why This Matters

- `sk_xxx` tokens are for other services (Slack, Stripe, etc.)
- GitHub won't recognize them
- That's why you get "401 Bad credentials"
- A proper GitHub token will authenticate correctly
# GitHub Token Setup

## Creating a GitHub Personal Access Token

1. Go to GitHub Settings > Developer settings > Personal access tokens > Tokens (classic)
   - Or visit: https://github.com/settings/tokens

2. Click "Generate new token" > "Generate new token (classic)"

3. Give your token a descriptive name like "Platform Code Reviews API"

4. Select the following scopes:
   - `repo` (Full control of private repositories)
     - This includes access to read pull requests, issues, and repository metadata
   - `read:org` (Read org and team membership)
     - Required to check if users are in the backend review group

5. Click "Generate token" and copy the token immediately (you won't be able to see it again)

## Setting up the token locally

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and add your token:
   ```
   GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
   ```

3. Make sure `.env` is in your `.gitignore` (it should be by default)

## Testing the token

Run this command to verify your token works:
```bash
rails runner "puts GithubService.new.rate_limit.remaining"
```

You should see a number (like 4999) indicating your remaining API calls.

## Token Permissions Required

The token needs these permissions to function properly:
- Read repository data (pull requests, issues)
- Read repository metadata
- Read organization team membership (for backend review group)
- Read commit statuses and checks

## Troubleshooting

If you get authentication errors:
1. Make sure the token hasn't expired
2. Verify the token has the correct scopes
3. Check that the `.env` file is being loaded (try `rails console` and type `ENV['GITHUB_TOKEN']`)
4. Ensure you're not hitting rate limits (5000 requests per hour for authenticated requests)
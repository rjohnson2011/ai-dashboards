# GitHub OAuth Setup Guide

This guide will help you set up GitHub OAuth authentication for the Platform Code Reviews application.

## Prerequisites

You need to be able to create OAuth Apps in GitHub. This can be done:
1. For personal testing: In your personal GitHub account settings
2. For production: In the department-of-veterans-affairs organization settings (requires admin access)

## Step 1: Create a GitHub OAuth App

1. Go to GitHub Settings:
   - Personal: https://github.com/settings/developers
   - Organization: https://github.com/organizations/department-of-veterans-affairs/settings/applications

2. Click "New OAuth App" (or "Register an application")

3. Fill in the following details:
   - **Application name**: `Platform Code Reviews` (or `Platform Code Reviews - Dev` for development)
   - **Homepage URL**: 
     - Development: `http://localhost:5173`
     - Production: `https://your-frontend-domain.com`
   - **Authorization callback URL**: 
     - Development: `http://localhost:3000/api/v1/auth/github/callback`
     - Production: `https://your-api-domain.com/api/v1/auth/github/callback`
   - **Enable Device Flow**: Leave unchecked

4. Click "Register application"

5. You'll see your **Client ID** on the next page

6. Click "Generate a new client secret" and copy the secret immediately (you won't be able to see it again)

## Step 2: Configure the Rails Application

1. Copy the `.env.example` file to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and add your OAuth credentials:
   ```
   # GitHub OAuth Configuration
   GITHUB_CLIENT_ID=your_client_id_here
   GITHUB_CLIENT_SECRET=your_client_secret_here
   
   # Frontend URL (for OAuth redirects)
   FRONTEND_URL=http://localhost:5173  # Change for production
   API_URL=http://localhost:3000       # Change for production
   ```

3. Run the database migration to create the users table:
   ```bash
   rails db:migrate
   ```

## Step 3: Update Frontend URLs

The frontend needs to know where the API is located. Update these as needed for your deployment.

## Step 4: Test the Authentication Flow

1. Start the Rails server:
   ```bash
   rails server
   ```

2. Visit: `http://localhost:3000/api/v1/auth/github`

3. You should be redirected to GitHub to authorize the application

4. After authorization, you'll be redirected back to the frontend with a JWT token

## Security Considerations

1. **Never commit** the `.env` file or expose your client secret
2. **Use HTTPS** in production for all URLs
3. **Rotate secrets** periodically
4. **Limit scope** - We only request `read:user` and `read:org` permissions

## How It Works

1. User clicks "Login with GitHub" on the frontend
2. Frontend redirects to `/api/v1/auth/github`
3. Rails redirects to GitHub OAuth with proper parameters
4. User authorizes on GitHub
5. GitHub redirects back to `/api/v1/auth/github/callback` with a code
6. Rails exchanges the code for an access token
7. Rails fetches user data and checks VA organization membership
8. Rails creates/updates the user record
9. Rails generates a JWT token and redirects to frontend with the token
10. Frontend stores the JWT and includes it in API requests

## Required Scopes

The application requests these GitHub OAuth scopes:
- `read:user` - Read user profile data
- `read:org` - Read organization membership (required to verify VA membership)

## Troubleshooting

### "Redirect URI mismatch" error
- Make sure the callback URL in your GitHub OAuth app settings exactly matches what's configured in the Rails app
- Check that `API_URL` in your `.env` file is correct

### "Bad credentials" error
- Verify your `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` are correct
- Make sure there are no extra spaces or newlines in the `.env` file

### Organization membership check fails
- Ensure the OAuth app has `read:org` scope
- The user must be a public member of the organization (private members may not be visible)

## Production Deployment

For production deployment on Render.com or similar:

1. Set environment variables in your hosting platform:
   ```
   GITHUB_CLIENT_ID=your_production_client_id
   GITHUB_CLIENT_SECRET=your_production_client_secret
   FRONTEND_URL=https://your-frontend-domain.vercel.app
   API_URL=https://your-api-domain.onrender.com
   ```

2. Update the GitHub OAuth app with production URLs

3. Ensure CORS is properly configured to allow your frontend domain
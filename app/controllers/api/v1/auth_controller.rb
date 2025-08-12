module Api
  module V1
    class AuthController < ApplicationController
      
      # GET /api/v1/auth/github
      # Redirects to GitHub OAuth
      def github
        redirect_to github_oauth_url, allow_other_host: true
      end
      
      # GET /api/v1/auth/github/callback
      # Handles OAuth callback from GitHub
      def github_callback
        # Exchange code for access token
        access_token = exchange_code_for_token(params[:code])
        
        if access_token.nil?
          return render json: { error: "Failed to authenticate with GitHub" }, status: :unauthorized
        end
        
        # Get user data from GitHub
        github_client = Octokit::Client.new(access_token: access_token)
        github_user = github_client.user
        
        # Find or create user
        user = User.from_github_oauth(github_user.to_h)
        user.access_token = access_token
        user.save!
        
        # Check VA membership
        user.check_va_membership!(github_client)
        
        # Generate JWT token
        jwt_token = user.generate_jwt_token
        
        # Redirect back to frontend with token
        redirect_to "#{frontend_url}/auth/callback?token=#{jwt_token}", allow_other_host: true
      rescue => e
        Rails.logger.error "GitHub OAuth error: #{e.message}"
        redirect_to "#{frontend_url}/auth/error?message=#{CGI.escape(e.message)}", allow_other_host: true
      end
      
      # GET /api/v1/auth/me
      # Returns current user info
      def me
        if current_user
          render json: {
            id: current_user.id,
            github_username: current_user.github_username,
            name: current_user.name,
            email: current_user.email,
            avatar_url: current_user.avatar_url,
            is_va_member: current_user.is_va_member,
            last_login_at: current_user.last_login_at
          }
        else
          render json: { error: "Not authenticated" }, status: :unauthorized
        end
      end
      
      # POST /api/v1/auth/logout
      def logout
        # Since we're using JWT, we don't need to do anything server-side
        # The client will remove the token
        render json: { message: "Logged out successfully" }
      end
      
      private
      
      def github_oauth_url
        client_id = ENV["GITHUB_CLIENT_ID"]
        redirect_uri = "#{api_url}/api/v1/auth/github/callback"
        scope = "read:user,read:org"
        
        "https://github.com/login/oauth/authorize?client_id=#{client_id}&redirect_uri=#{CGI.escape(redirect_uri)}&scope=#{scope}"
      end
      
      def exchange_code_for_token(code)
        client_id = ENV["GITHUB_CLIENT_ID"]
        client_secret = ENV["GITHUB_CLIENT_SECRET"]
        
        response = Faraday.post("https://github.com/login/oauth/access_token") do |req|
          req.headers["Accept"] = "application/json"
          req.body = {
            client_id: client_id,
            client_secret: client_secret,
            code: code
          }
        end
        
        data = JSON.parse(response.body)
        data["access_token"]
      rescue => e
        Rails.logger.error "Failed to exchange code for token: #{e.message}"
        nil
      end
      
      def frontend_url
        ENV["FRONTEND_URL"] || "http://localhost:5173"
      end
      
      def api_url
        ENV["API_URL"] || "http://localhost:3000"
      end
    end
  end
end
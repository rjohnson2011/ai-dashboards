module Api
  module V1
    class AdminController < ApplicationController
      def initialize_data
        # Simple auth check - you should use a proper admin auth in production
        unless params[:token] == ENV['ADMIN_TOKEN']
          render json: { error: 'Unauthorized' }, status: :unauthorized
          return
        end

        # Clear any locks
        Rails.cache.delete('pull_request_data_updating')
        
        # Fetch basic PR data quickly
        github_token = ENV['GITHUB_TOKEN']
        owner = ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs'
        repo = ENV['GITHUB_REPO'] || 'vets-api'
        
        client = Octokit::Client.new(access_token: github_token)
        prs = client.pull_requests("#{owner}/#{repo}", state: 'open', per_page: 100)
        
        count = 0
        prs.each do |pr_data|
          pr = PullRequest.find_or_initialize_by(number: pr_data[:number])
          pr.update!(
            github_id: pr_data[:id],
            title: pr_data[:title],
            author: pr_data[:user][:login],
            state: pr_data[:state],
            url: pr_data[:html_url],
            pr_created_at: pr_data[:created_at],
            pr_updated_at: pr_data[:updated_at],
            draft: pr_data[:draft] || false,
            ci_status: 'pending',
            backend_approval_status: 'not_approved',
            total_checks: 0,
            successful_checks: 0,
            failed_checks: 0
          )
          count += 1
        end
        
        render json: { 
          message: 'Data initialized successfully', 
          pull_requests_created: count,
          note: 'CI status will be updated in the background'
        }
      end
    end
  end
end
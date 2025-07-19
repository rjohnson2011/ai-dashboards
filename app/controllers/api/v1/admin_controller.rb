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
      
      def update_data
        # Simple auth check
        unless params[:token] == ENV['ADMIN_TOKEN']
          render json: { error: 'Unauthorized' }, status: :unauthorized
          return
        end
        
        # Run the update synchronously
        begin
          service = GithubPullRequestService.new
          service.fetch_and_update_pull_requests
          
          render json: { 
            message: 'Data updated successfully',
            pull_requests: PullRequest.count,
            last_updated: Time.current
          }
        rescue => e
          render json: { 
            error: 'Failed to update data',
            message: e.message 
          }, status: :internal_server_error
        end
      end
      
      def update_full_data
        # Simple auth check
        unless params[:token] == ENV['ADMIN_TOKEN']
          render json: { error: 'Unauthorized' }, status: :unauthorized
          return
        end
        
        updated_count = 0
        errors = []
        
        PullRequest.find_each do |pr|
          begin
            # Fetch CI checks
            scraper = EnhancedGithubScraperService.new
            check_data = scraper.scrape_pr_checks_detailed(pr.url)
            
            # Update PR with check data
            pr.update!(
              ci_status: check_data[:overall_status] || 'pending',
              total_checks: check_data[:total_checks] || 0,
              successful_checks: check_data[:successful_checks] || 0,
              failed_checks: check_data[:failed_checks] || 0
            )
            
            # Store failing checks in Rails cache
            if check_data[:checks] && check_data[:checks].any? { |c| c[:status] == 'failure' }
              failing_checks = check_data[:checks].select { |c| c[:status] == 'failure' }
              Rails.cache.write("pr_#{pr.id}_failing_checks", failing_checks, expires_in: 1.hour)
            end
            
            # Fetch reviews
            github_token = ENV['GITHUB_TOKEN']
            owner = ENV['GITHUB_OWNER'] || 'department-of-veterans-affairs'
            repo = ENV['GITHUB_REPO'] || 'vets-api'
            client = Octokit::Client.new(access_token: github_token)
            
            reviews = client.pull_request_reviews("#{owner}/#{repo}", pr.number)
            reviews.each do |review_data|
              PullRequestReview.find_or_create_by(
                pull_request_id: pr.id,
                github_id: review_data[:id]
              ).update!(
                user: review_data[:user][:login],
                state: review_data[:state],
                submitted_at: review_data[:submitted_at]
              )
            end
            
            # Update backend approval
            pr.update_backend_approval_status!
            
            updated_count += 1
          rescue => e
            errors << "PR ##{pr.number}: #{e.message}"
          end
        end
        
        render json: { 
          message: 'Full data update completed',
          updated_count: updated_count,
          total_prs: PullRequest.count,
          errors: errors.take(10) # Only show first 10 errors
        }
      end
    end
  end
end
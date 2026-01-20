require "rake"

module Api
  module V1
    class AdminController < ApplicationController
      def initialize_data
        # Simple auth check - you should use a proper admin auth in production
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        # Clear any locks
        Rails.cache.delete("pull_request_data_updating")

        # Fetch basic PR data quickly
        github_token = ENV["GITHUB_TOKEN"]
        owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
        repo = ENV["GITHUB_REPO"] || "vets-api"

        client = Octokit::Client.new(access_token: github_token)
        prs = client.pull_requests("#{owner}/#{repo}", state: "open", per_page: 100)

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
            ci_status: "pending",
            backend_approval_status: "not_approved",
            total_checks: 0,
            successful_checks: 0,
            failed_checks: 0
          )
          count += 1
        end

        render json: {
          message: "Data initialized successfully",
          pull_requests_created: count,
          note: "CI status will be updated in the background"
        }
      end

      def update_data
        # Simple auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        # First, cleanup merged/closed PRs
        cleanup_stats = cleanup_merged_prs_internal

        # Then fetch new open PRs
        begin
          github_token = ENV["GITHUB_TOKEN"]
          owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
          repo = ENV["GITHUB_REPO"] || "vets-api"

          client = Octokit::Client.new(access_token: github_token)
          prs = client.pull_requests("#{owner}/#{repo}", state: "open", per_page: 100)

          new_count = 0
          updated_count = 0

          prs.each do |pr_data|
            pr = PullRequest.find_or_initialize_by(number: pr_data[:number])
            is_new = pr.new_record?

            pr.update!(
              github_id: pr_data[:id],
              title: pr_data[:title],
              author: pr_data[:user][:login],
              state: pr_data[:state],
              url: pr_data[:html_url],
              pr_created_at: pr_data[:created_at],
              pr_updated_at: pr_data[:updated_at],
              draft: pr_data[:draft] || false
            )

            if is_new
              new_count += 1
            else
              updated_count += 1
            end
          end

          render json: {
            message: "Data updated successfully",
            new_prs: new_count,
            updated_prs: updated_count,
            cleanup_stats: cleanup_stats,
            total_open_prs: PullRequest.where(state: "open").count,
            last_updated: Time.current
          }
        rescue => e
          render json: {
            error: "Failed to update data",
            message: e.message
          }, status: :internal_server_error
        end
      end

      def update_full_data
        # Simple auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
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
              ci_status: check_data[:overall_status] || "pending",
              total_checks: check_data[:total_checks] || 0,
              successful_checks: check_data[:successful_checks] || 0,
              failed_checks: check_data[:failed_checks] || 0
            )

            # Store failing checks in Rails cache
            if check_data[:checks] && check_data[:checks].any? { |c| c[:status] == "failure" }
              failing_checks = check_data[:checks].select { |c| c[:status] == "failure" }
              Rails.cache.write("pr_#{pr.id}_failing_checks", failing_checks, expires_in: 1.hour)
            end

            # Fetch reviews
            github_token = ENV["GITHUB_TOKEN"]
            owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
            repo = ENV["GITHUB_REPO"] || "vets-api"
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
          message: "Full data update completed",
          updated_count: updated_count,
          total_prs: PullRequest.count,
          errors: errors.take(10) # Only show first 10 errors
        }
      end

      def cleanup_merged_prs
        # Simple auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        github_token = ENV["GITHUB_TOKEN"]
        owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
        repo = ENV["GITHUB_REPO"] || "vets-api"
        client = Octokit::Client.new(access_token: github_token)

        updated_count = 0
        deleted_count = 0

        # Check all "open" PRs to see if they're actually closed/merged
        PullRequest.where(state: "open").find_each do |pr|
          begin
            github_pr = client.pull_request("#{owner}/#{repo}", pr.number)

            if github_pr.state == "closed"
              if github_pr.merged
                pr.update!(state: "merged")
                updated_count += 1
              else
                pr.update!(state: "closed")
                updated_count += 1
              end
            end
          rescue Octokit::NotFound
            # PR was deleted
            pr.destroy
            deleted_count += 1
          rescue => e
            Rails.logger.error "Error checking PR ##{pr.number}: #{e.message}"
          end
        end

        render json: {
          message: "Cleanup completed",
          updated_to_merged_or_closed: updated_count,
          deleted: deleted_count,
          remaining_open: PullRequest.where(state: "open").count
        }
      end

      def update_checks_via_api
        # Simple auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        # Use GitHub API to get accurate check data
        checks_service = GithubChecksApiService.new

        if params[:pr_number]
          # Update single PR
          success = checks_service.update_pr_with_checks(params[:pr_number].to_i)
          pr = PullRequest.find_by(number: params[:pr_number])

          render json: {
            message: success ? "PR checks updated successfully" : "Failed to update PR checks",
            pr_number: params[:pr_number],
            total_checks: pr&.total_checks,
            successful_checks: pr&.successful_checks,
            failed_checks: pr&.failed_checks,
            ci_status: pr&.ci_status
          }
        else
          # Update all PRs
          result = checks_service.update_all_prs_with_checks
          render json: {
            message: "All PR checks updated",
            updated: result[:updated],
            errors: result[:errors]
          }
        end
      end

      def background_job_logs
        # Simple auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        log_file = "/tmp/background_jobs.log"
        if File.exist?(log_file)
          logs = File.read(log_file).split("\n").last(50) # Last 50 lines
          render json: {
            logs: logs,
            file_size: File.size(log_file),
            last_modified: File.mtime(log_file),
            current_time: Time.current
          }
        else
          render json: {
            error: "Log file not found",
            message: "Background jobs may not have started yet",
            current_time: Time.current
          }
        end
      end

      def cron_status
        # Simple auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        # Get recent cron job logs
        recent_logs = CronJobLog.order(started_at: :desc).limit(10)

        # Get last successful run
        last_success = CronJobLog.where(status: "completed").order(started_at: :desc).first

        # Get last failure
        last_failure = CronJobLog.where(status: "failed").order(started_at: :desc).first

        # Calculate stats
        last_24h = CronJobLog.where("started_at > ?", 24.hours.ago)

        render json: {
          last_success: last_success ? {
            started_at: last_success.started_at,
            completed_at: last_success.completed_at,
            duration_seconds: last_success.completed_at ? (last_success.completed_at - last_success.started_at).round(2) : nil,
            prs_processed: last_success.prs_processed,
            prs_updated: last_success.prs_updated
          } : nil,
          last_failure: last_failure ? {
            started_at: last_failure.started_at,
            error_class: last_failure.error_class,
            error_message: last_failure.error_message,
            error_location: last_failure.error_backtrace&.lines&.first
          } : nil,
          stats_24h: {
            total_runs: last_24h.count,
            successful: last_24h.where(status: "completed").count,
            failed: last_24h.where(status: "failed").count,
            running: last_24h.where(status: "running").count
          },
          recent_logs: recent_logs.map do |log|
            {
              id: log.id,
              status: log.status,
              started_at: log.started_at,
              completed_at: log.completed_at,
              duration_seconds: log.completed_at && log.started_at ? (log.completed_at - log.started_at).round(2) : nil,
              prs_processed: log.prs_processed,
              error_class: log.error_class,
              error_message: log.error_message&.truncate(200)
            }
          end
        }
      end

      def run_task
        # Simple auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        task_name = params[:task]
        task_args = params[:args] || []

        begin
          # Load Rails tasks
          Rails.application.load_tasks unless Rake::Task.task_defined?(task_name)

          # Run the rake task
          Rake::Task[task_name].invoke(*task_args)

          render json: { success: true, message: "Task #{task_name} completed successfully" }
        rescue => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      def manual_scraper_run
        # Simple auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        repo_name = params[:repository_name] || ENV["GITHUB_REPO"] || "vets-api"
        repo_owner = params[:repository_owner] || ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"

        Rails.logger.info "[AdminController] Manual scraper run initiated for #{repo_owner}/#{repo_name}"

        # Run synchronously - the :async adapter loses jobs on server restart/sleep
        # GHA triggers this every 15 min so it's better to run inline
        started_at = Time.current
        begin
          FetchAllPullRequestsJob.perform_now(
            repository_name: repo_name,
            repository_owner: repo_owner
          )

          render json: {
            success: true,
            message: "Scraper completed successfully",
            repository: "#{repo_owner}/#{repo_name}",
            started_at: started_at,
            completed_at: Time.current,
            duration_seconds: (Time.current - started_at).round(2)
          }
        rescue => e
          Rails.logger.error "[AdminController] Scraper failed: #{e.message}"
          render json: {
            success: false,
            message: "Scraper failed: #{e.message}",
            repository: "#{repo_owner}/#{repo_name}",
            started_at: started_at,
            failed_at: Time.current
          }, status: :internal_server_error
        end
      end

      def verify_scraper_version
        # Auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        # Get commit hash
        git_commit = `git rev-parse HEAD 2>/dev/null`.strip rescue "unknown"

        render json: {
          status: "ok",
          git_commit: git_commit[0..7],
          git_commit_full: git_commit,
          hybrid_pr_checker_exists: defined?(HybridPrCheckerService).present?,
          enhanced_scraper_exists: defined?(EnhancedGithubScraperService).present?,
          fetch_all_pull_requests_job_path: FetchAllPullRequestsJob.instance_method(:fetch_pr_checks_inline).source_location&.first,
          timestamp: Time.current
        }
      end

      def backend_members
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        members = BackendReviewGroupMember.pluck(:username)

        render json: {
          count: members.count,
          members: members,
          last_synced: BackendReviewGroupMember.maximum(:updated_at)
        }
      end

      def refresh_backend_members
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        result = FetchBackendReviewGroupService.call

        render json: {
          success: result[:success],
          count: result[:count],
          error: result[:error],
          members: BackendReviewGroupMember.pluck(:username)
        }
      end

      def debug_pr
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        pr_number = params[:pr_number].to_i
        pr = PullRequest.find_by(number: pr_number)

        unless pr
          render json: { error: "PR not found" }, status: :not_found
          return
        end

        # Get all reviews from DB
        db_reviews = pr.pull_request_reviews.map do |r|
          { user: r.user, state: r.state, submitted_at: r.submitted_at }
        end

        # Calculate what backend approval status would be
        reviews_by_user = pr.pull_request_reviews.group_by(&:user)
        latest_reviews = reviews_by_user.map { |_user, reviews| reviews.max_by(&:submitted_at) }
        approved_users = latest_reviews.select { |r| r.state == "APPROVED" }.map(&:user)
        backend_members = BackendReviewGroupMember.pluck(:username)
        intersection = approved_users & backend_members

        # If fix param is passed, actually update the backend_approval_status
        if params[:fix] == "true"
          old_status = pr.backend_approval_status
          pr.update_backend_approval_status!
          pr.reload
          new_status = pr.backend_approval_status
        end

        render json: {
          pr_number: pr_number,
          backend_approval_status: pr.backend_approval_status,
          db_reviews_count: db_reviews.count,
          db_reviews: db_reviews,
          latest_reviews: latest_reviews.map { |r| { user: r.user, state: r.state } },
          approved_users: approved_users,
          backend_members: backend_members,
          intersection: intersection,
          should_be_approved: intersection.any?,
          fixed: params[:fix] == "true",
          old_status: old_status,
          new_status: new_status
        }
      end

      def fix_all_pr_statuses
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        updated = 0
        errors = []

        PullRequest.where(state: "open").find_each do |pr|
          old_status = pr.backend_approval_status
          pr.update_backend_approval_status!
          pr.update_ready_for_backend_review!
          pr.update_approval_status!

          if pr.backend_approval_status != old_status
            updated += 1
            Rails.logger.info "[FixAllPRStatuses] PR ##{pr.number}: #{old_status} -> #{pr.backend_approval_status}"
          end
        rescue StandardError => e
          errors << { pr_number: pr.number, error: e.message }
        end

        render json: {
          success: true,
          updated_count: updated,
          errors: errors
        }
      end

      private

      def cleanup_merged_prs_internal
        github_token = ENV["GITHUB_TOKEN"]
        owner = ENV["GITHUB_OWNER"] || "department-of-veterans-affairs"
        repo = ENV["GITHUB_REPO"] || "vets-api"
        client = Octokit::Client.new(access_token: github_token)

        updated_count = 0
        deleted_count = 0

        # Check all "open" PRs to see if they're actually closed/merged
        PullRequest.where(state: "open").find_each do |pr|
          begin
            github_pr = client.pull_request("#{owner}/#{repo}", pr.number)

            if github_pr.state == "closed"
              if github_pr.merged
                pr.update!(state: "merged")
                updated_count += 1
              else
                pr.update!(state: "closed")
                updated_count += 1
              end
            end
          rescue Octokit::NotFound
            # PR was deleted
            pr.destroy
            deleted_count += 1
          rescue => e
            Rails.logger.error "Error checking PR ##{pr.number}: #{e.message}"
          end
        end

        { updated_to_merged_or_closed: updated_count, deleted: deleted_count }
      end

      def webhook_events
        # Simple auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        events = WebhookEvent.recent.limit(100)

        # Get summary stats
        stats = {
          total_events_24h: WebhookEvent.where("created_at > ?", 24.hours.ago).count,
          failed_events_24h: WebhookEvent.failed.where("created_at > ?", 24.hours.ago).count,
          events_by_type: WebhookEvent.where("created_at > ?", 24.hours.ago).group(:event_type).count
        }

        render json: {
          stats: stats,
          recent_events: events.map do |event|
            {
              id: event.id,
              event_type: event.event_type,
              github_delivery_id: event.github_delivery_id,
              status: event.status,
              error_message: event.error_message,
              pull_request_number: event.pull_request_number,
              created_at: event.created_at,
              processed_at: event.processed_at,
              processing_time: event.processed_at ? (event.processed_at - event.created_at).round(2) : nil
            }
          end
        }
      end

      def debug_token
        # Simple auth check
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        debug_info = {
          environment: ENV["RAILS_ENV"],
          github_token_present: ENV["GITHUB_TOKEN"].present?,
          github_token_length: ENV["GITHUB_TOKEN"]&.length || 0,
          github_owner: ENV["GITHUB_OWNER"],
          github_repo: ENV["GITHUB_REPO"]
        }

        if ENV["GITHUB_TOKEN"].present?
          begin
            client = Octokit::Client.new(access_token: ENV["GITHUB_TOKEN"])
            user = client.user
            rate_limit = client.rate_limit

            debug_info[:authentication] = {
              valid: true,
              user: user.login,
              rate_limit: {
                limit: rate_limit.limit,
                remaining: rate_limit.remaining,
                resets_at: rate_limit.resets_at
              }
            }
          rescue Octokit::Unauthorized => e
            debug_info[:authentication] = {
              valid: false,
              error: "Invalid token: #{e.message}"
            }
          rescue => e
            debug_info[:authentication] = {
              valid: false,
              error: e.message
            }
          end
        else
          debug_info[:error] = "GITHUB_TOKEN not set"
        end

        render json: debug_info
      end
    end
  end
end

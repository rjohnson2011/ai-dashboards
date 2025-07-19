class Api::V1::GithubWebhooksController < ApplicationController
  # API mode doesn't have CSRF protection
  before_action :verify_webhook_signature
  
  def create
    event_type = request.headers['X-GitHub-Event']
    delivery_id = request.headers['X-GitHub-Delivery']
    
    # Log the webhook event
    webhook_event = WebhookEvent.create!(
      event_type: event_type,
      github_delivery_id: delivery_id,
      payload: request.raw_post,
      status: 'processing'
    )
    
    case event_type
    when 'pull_request'
      handle_pull_request_event
    when 'pull_request_review'
      handle_pull_request_review_event
    when 'check_suite'
      handle_check_suite_event
    when 'check_run'
      handle_check_run_event
    when 'status'
      handle_status_event
    when 'ping'
      handle_ping_event
    else
      Rails.logger.info "[Webhook] Received unhandled event type: #{event_type}"
    end
    
    webhook_event.update!(status: 'completed', processed_at: Time.current)
    head :ok
  rescue => e
    Rails.logger.error "[Webhook] Error processing webhook: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    webhook_event&.update!(
      status: 'failed',
      error_message: "#{e.class}: #{e.message}",
      processed_at: Time.current
    )
    
    head :internal_server_error
  end
  
  private
  
  def verify_webhook_signature
    request_body = request.raw_post
    signature = 'sha256=' + OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new('sha256'),
      webhook_secret,
      request_body
    )
    
    unless Rack::Utils.secure_compare(signature, request.headers['X-Hub-Signature-256'])
      Rails.logger.error "[Webhook] Invalid signature"
      head :unauthorized
    end
  end
  
  def webhook_secret
    ENV['GITHUB_WEBHOOK_SECRET'] || Rails.application.credentials.github_webhook_secret
  end
  
  def handle_pull_request_event
    payload = JSON.parse(request.raw_post)
    action = payload['action']
    pr_data = payload['pull_request']
    
    Rails.logger.info "[Webhook] Pull request #{action}: ##{pr_data['number']}"
    
    case action
    when 'opened', 'reopened', 'synchronize', 'edited'
      # Update or create PR
      pr = PullRequest.find_or_initialize_by(number: pr_data['number'])
      pr.update!(
        github_id: pr_data['id'],
        title: pr_data['title'],
        author: pr_data['user']['login'],
        state: pr_data['state'],
        url: pr_data['html_url'],
        pr_created_at: pr_data['created_at'],
        pr_updated_at: pr_data['updated_at'],
        draft: pr_data['draft'] || false,
        head_sha: pr_data['head']['sha']
      )
      
      # Queue job to fetch check details
      FetchPullRequestChecksJob.perform_later(pr.id)
      
    when 'closed'
      # Mark PR as closed or merged
      pr = PullRequest.find_by(number: pr_data['number'])
      if pr
        pr.update!(state: pr_data['merged'] ? 'merged' : 'closed')
      end
    end
  end
  
  def handle_pull_request_review_event
    payload = JSON.parse(request.raw_post)
    action = payload['action']
    review_data = payload['review']
    pr_data = payload['pull_request']
    
    Rails.logger.info "[Webhook] PR review #{action} on ##{pr_data['number']}"
    
    if action == 'submitted'
      pr = PullRequest.find_by(number: pr_data['number'])
      return unless pr
      
      # Create or update review
      review = PullRequestReview.find_or_create_by(
        pull_request_id: pr.id,
        github_id: review_data['id']
      )
      
      review.update!(
        user: review_data['user']['login'],
        state: review_data['state'],
        submitted_at: review_data['submitted_at']
      )
      
      # Update approval statuses
      pr.update_backend_approval_status!
      pr.update_ready_for_backend_review!
      pr.update_approval_status!
    end
  end
  
  def handle_check_suite_event
    payload = JSON.parse(request.raw_post)
    action = payload['action']
    check_suite = payload['check_suite']
    
    # Find associated PRs
    pr_numbers = check_suite['pull_requests'].map { |pr| pr['number'] }
    
    Rails.logger.info "[Webhook] Check suite #{action} for PRs: #{pr_numbers.join(', ')}"
    
    if ['completed', 'requested', 'rerequested'].include?(action)
      pr_numbers.each do |pr_number|
        pr = PullRequest.find_by(number: pr_number)
        next unless pr
        
        # Queue job to update checks
        FetchPullRequestChecksJob.perform_later(pr.id)
      end
    end
  end
  
  def handle_check_run_event
    payload = JSON.parse(request.raw_post)
    action = payload['action']
    check_run = payload['check_run']
    
    # Find associated PRs
    pr_numbers = check_run['pull_requests'].map { |pr| pr['number'] }
    
    Rails.logger.info "[Webhook] Check run #{action} (#{check_run['name']}) for PRs: #{pr_numbers.join(', ')}"
    
    if ['created', 'completed', 'rerequested'].include?(action)
      pr_numbers.each do |pr_number|
        pr = PullRequest.find_by(number: pr_number)
        next unless pr
        
        # Queue job to update checks
        FetchPullRequestChecksJob.perform_later(pr.id)
      end
    end
  end
  
  def handle_status_event
    payload = JSON.parse(request.raw_post)
    commit_sha = payload['sha']
    status = payload['state']
    context = payload['context']
    
    Rails.logger.info "[Webhook] Status update for commit #{commit_sha[0..7]}: #{context} is #{status}"
    
    # Find PRs with this commit SHA
    prs = PullRequest.where(head_sha: commit_sha)
    
    prs.each do |pr|
      Rails.logger.info "[Webhook] Updating checks for PR ##{pr.number} due to status update"
      FetchPullRequestChecksJob.perform_later(pr.id)
    end
  end
  
  def handle_ping_event
    Rails.logger.info "[Webhook] Ping received - webhook configured successfully!"
  end
end
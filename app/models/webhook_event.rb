class WebhookEvent < ApplicationRecord
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :failed, -> { where(status: 'failed') }
  scope :completed, -> { where(status: 'completed') }
  scope :by_type, ->(type) { where(event_type: type) }
  
  # Cleanup old events (keep last 7 days)
  def self.cleanup_old_events
    where('created_at < ?', 7.days.ago).destroy_all
  end
  
  # Parse payload JSON
  def parsed_payload
    JSON.parse(payload) rescue {}
  end
  
  # Get PR number if applicable
  def pull_request_number
    case event_type
    when 'pull_request', 'pull_request_review'
      parsed_payload.dig('pull_request', 'number')
    when 'check_suite', 'check_run'
      parsed_payload.dig('check_suite', 'pull_requests', 0, 'number') ||
      parsed_payload.dig('check_run', 'pull_requests', 0, 'number')
    end
  end
end

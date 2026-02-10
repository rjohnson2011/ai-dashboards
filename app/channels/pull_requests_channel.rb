class PullRequestsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "pull_requests"
    Rails.logger.info "[ActionCable] Client subscribed to pull_requests channel"
  end

  def unsubscribed
    Rails.logger.info "[ActionCable] Client unsubscribed from pull_requests channel"
  end
end

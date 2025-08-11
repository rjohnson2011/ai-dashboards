class FetchBackendReviewGroupJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting fetch of backend review group members"
    result = FetchBackendReviewGroupService.call

    if result[:success]
      Rails.logger.info "Successfully fetched backend review group members: #{result[:count]} members"
    else
      Rails.logger.error "Failed to fetch backend review group members: #{result[:error]}"
    end
  end
end

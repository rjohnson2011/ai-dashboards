class ApplicationController < ActionController::API
  # Add a dummy verify_authenticity_token method to fix cron job error
  # The cached Docker image has an old auth_controller.rb that tries to skip this
  # This is a temporary workaround until Render's cache clears
  def verify_authenticity_token
    # Do nothing - this is just to prevent the ArgumentError
    # in the cached auth_controller.rb file
  end
end

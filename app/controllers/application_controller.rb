class ApplicationController < ActionController::API
  # Legacy callback retained because a previously-deployed image referenced it.
  before_action :verify_authenticity_token

  def verify_authenticity_token
    # No-op — exists only to satisfy historical skip_before_action calls.
  end

  before_action :require_google_auth!

  attr_reader :current_user

  private

  def require_google_auth!
    token = bearer_token
    @current_user = GoogleTokenVerifier.call(token)
  rescue GoogleTokenVerifier::DisallowedDomain => e
    render json: { error: "Forbidden", reason: e.message }, status: :forbidden
  rescue GoogleTokenVerifier::InvalidToken, Google::Auth::Error => e
    render json: { error: "Unauthorized", reason: e.message }, status: :unauthorized
  end

  def bearer_token
    auth = request.headers["Authorization"].to_s
    auth.start_with?("Bearer ") ? auth.sub("Bearer ", "") : nil
  end
end

class Api::V1::AuthController < ApplicationController
  # Exchanging a Google ID token for an API session must succeed even
  # though the request doesn't carry our own session token yet — Google
  # auth is the gate.
  skip_before_action :require_google_auth!, only: :session

  # POST /api/v1/auth/session
  # Body / params: { id_token: "<google-id-jwt>" }
  # Response: { token: "pcr_...", email, name, picture, exp }
  def session
    id_token = params[:id_token].to_s

    user = GoogleTokenVerifier.call(id_token)

    api_token = SessionTokenService.issue_with_prefix(
      email: user.email,
      name: user.name,
      picture: user.picture,
      sub: user.sub
    )

    render json: {
      token: api_token,
      email: user.email,
      name: user.name,
      picture: user.picture,
      expires_in: SessionTokenService::TTL.to_i
    }
  rescue GoogleTokenVerifier::DisallowedDomain => e
    render json: { error: "Forbidden", reason: e.message }, status: :forbidden
  rescue GoogleTokenVerifier::InvalidToken, Google::Auth::Error => e
    render json: { error: "Unauthorized", reason: e.message }, status: :unauthorized
  end
end

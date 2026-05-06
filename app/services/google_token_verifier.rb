require "googleauth"

class GoogleTokenVerifier
  Result = Struct.new(:email, :name, :picture, :sub, keyword_init: true)

  class InvalidToken < StandardError; end
  class DisallowedDomain < StandardError; end

  def self.call(id_token)
    new.call(id_token)
  end

  def call(id_token)
    raise InvalidToken, "missing token" if id_token.blank?

    payload = verifier.verify(id_token)
    raise InvalidToken, "could not verify token" unless payload
    raise InvalidToken, "email not verified" unless payload["email_verified"]

    email = payload["email"].to_s.downcase
    raise DisallowedDomain, "email #{email} not in allowed domains" unless allowed_email?(email)

    Result.new(
      email: email,
      name: payload["name"],
      picture: payload["picture"],
      sub: payload["sub"]
    )
  end

  private

  def verifier
    @verifier ||= Google::Auth::IDTokens::Verifier.new(aud: client_id)
  end

  def client_id
    ENV.fetch("GOOGLE_CLIENT_ID") { raise InvalidToken, "GOOGLE_CLIENT_ID not configured" }
  end

  def allowed_email?(email)
    domain = email.split("@", 2).last
    allowed_domains.any? { |allowed| domain == allowed }
  end

  def allowed_domains
    ENV.fetch("ALLOWED_EMAIL_DOMAINS", "oddball.io,adhocteam.us,va.gov").split(",").map { |d| d.strip.downcase }
  end
end

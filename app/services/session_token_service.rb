require "openssl"
require "base64"
require "json"

# Mints and verifies long-lived API session JWTs.
#
# After a user logs in with Google, we issue our own JWT signed with
# Rails.application.secret_key_base so they don't have to re-authenticate
# every hour when the Google ID token expires. This is HS256 — fine for a
# single-deployment app where signer == verifier.
class SessionTokenService
  TTL = 365.days
  ALG = "HS256"
  ISSUER = "platform-code-reviews"

  class InvalidToken < StandardError; end

  def self.issue(email:, name: nil, picture: nil, sub: nil)
    now = Time.current.to_i
    payload = {
      iss: ISSUER,
      sub: sub || email,
      email: email,
      name: name,
      picture: picture,
      iat: now,
      exp: now + TTL.to_i
    }
    encode(payload)
  end

  def self.verify(token)
    raise InvalidToken, "missing token" if token.blank?

    header_b64, payload_b64, sig_b64 = token.split(".")
    raise InvalidToken, "malformed token" unless header_b64 && payload_b64 && sig_b64

    expected_sig = sign("#{header_b64}.#{payload_b64}")
    raise InvalidToken, "bad signature" unless secure_compare(sig_b64, expected_sig)

    payload = JSON.parse(b64_decode(payload_b64))
    raise InvalidToken, "wrong issuer" unless payload["iss"] == ISSUER
    raise InvalidToken, "expired" if payload["exp"].to_i < Time.current.to_i

    payload
  end

  def self.encode(payload)
    header = { alg: ALG, typ: "JWT" }
    header_b64 = b64_encode(header.to_json)
    payload_b64 = b64_encode(payload.to_json)
    sig = sign("#{header_b64}.#{payload_b64}")
    "#{header_b64}.#{payload_b64}.#{sig}"
  end

  def self.sign(input)
    digest = OpenSSL::HMAC.digest("SHA256", secret, input)
    b64_encode(digest)
  end

  def self.secret
    Rails.application.secret_key_base
  end

  def self.b64_encode(bytes)
    Base64.urlsafe_encode64(bytes, padding: false)
  end

  def self.b64_decode(str)
    Base64.urlsafe_decode64(str + "=" * ((4 - str.length % 4) % 4))
  end

  def self.secure_compare(a, b)
    return false unless a.bytesize == b.bytesize
    ActiveSupport::SecurityUtils.secure_compare(a, b)
  end

  # API token starts with this prefix so verifier can route correctly.
  TOKEN_PREFIX = "pcr_"

  def self.api_token?(token)
    token.to_s.start_with?(TOKEN_PREFIX)
  end

  def self.strip_prefix(token)
    token.sub(/\A#{Regexp.escape(TOKEN_PREFIX)}/, "")
  end

  def self.issue_with_prefix(**)
    TOKEN_PREFIX + issue(**)
  end
end

class User < ApplicationRecord
  # Validations
  validates :github_id, presence: true, uniqueness: true
  validates :github_username, presence: true, uniqueness: true
  
  # Encrypt access token
  encrypts :access_token, deterministic: false
  
  # Find or create user from GitHub OAuth data
  def self.from_github_oauth(auth_hash)
    user = find_or_initialize_by(github_id: auth_hash["id"])
    
    user.update!(
      github_username: auth_hash["login"],
      email: auth_hash["email"],
      name: auth_hash["name"],
      avatar_url: auth_hash["avatar_url"],
      last_login_at: Time.current
    )
    
    user
  end
  
  # Check if user is member of VA organization
  def check_va_membership!(github_client)
    is_member = github_client.organization_member?(
      "department-of-veterans-affairs", 
      github_username
    )
    
    update!(is_va_member: is_member)
    is_member
  rescue Octokit::NotFound, Octokit::Forbidden
    update!(is_va_member: false)
    false
  end
  
  # Generate JWT token for authentication
  def generate_jwt_token
    payload = {
      user_id: id,
      github_id: github_id,
      github_username: github_username,
      is_va_member: is_va_member,
      exp: 24.hours.from_now.to_i
    }
    
    JWT.encode(payload, Rails.application.credentials.secret_key_base)
  end
end
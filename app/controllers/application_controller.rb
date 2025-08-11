class ApplicationController < ActionController::API
  before_action :set_current_user
  
  private
  
  def set_current_user
    @current_user = authenticate_user_from_token
  end
  
  def current_user
    @current_user
  end
  
  def authenticate_user_from_token
    token = extract_token_from_header
    return nil unless token
    
    payload = JWT.decode(token, Rails.application.credentials.secret_key_base)[0]
    User.find_by(id: payload["user_id"])
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
  
  def extract_token_from_header
    auth_header = request.headers["Authorization"]
    return nil unless auth_header
    
    # Extract token from "Bearer <token>" format
    auth_header.split(" ").last
  end
  
  def require_authentication!
    unless current_user
      render json: { error: "Authentication required" }, status: :unauthorized
    end
  end
  
  def require_va_membership!
    require_authentication!
    
    unless current_user&.is_va_member
      render json: { error: "Must be a member of department-of-veterans-affairs organization" }, status: :forbidden
    end
  end
end
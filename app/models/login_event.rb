class LoginEvent < ApplicationRecord
  validates :email, presence: true
  validates :logged_in_at, presence: true
end

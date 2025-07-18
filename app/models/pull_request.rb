class PullRequest < ApplicationRecord
  has_many :check_runs, dependent: :destroy
  
  validates :github_id, presence: true, uniqueness: true
  validates :number, presence: true
  validates :title, presence: true
  validates :author, presence: true
  validates :state, presence: true
  validates :url, presence: true
  
  scope :open, -> { where(state: 'open') }
  scope :closed, -> { where(state: 'closed') }
  scope :draft, -> { where(draft: true) }
  scope :ready, -> { where(draft: false) }
  
  def failing_checks
    check_runs.where(status: ['failure', 'error', 'cancelled'])
  end
  
  def passing_checks
    check_runs.where(status: 'success')
  end
  
  def required_checks
    check_runs.where(required: true)
  end
  
  def required_failing_checks
    required_checks.where(status: ['failure', 'error', 'cancelled'])
  end
  
  def overall_status
    # If any required checks are failing, status is failure
    return 'failure' if required_failing_checks.any?
    
    # If all required checks are passing, status is success
    return 'success' if required_checks.any? && required_failing_checks.empty?
    
    # If there are no required checks, use overall check status
    return 'failure' if failing_checks.any?
    return 'success' if passing_checks.any?
    
    'pending'
  end
end

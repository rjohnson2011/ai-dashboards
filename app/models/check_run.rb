class CheckRun < ApplicationRecord
  belongs_to :pull_request
  
  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: ['success', 'failure', 'pending', 'error', 'cancelled', 'skipped', 'unknown'] }
  
  scope :successful, -> { where(status: 'success') }
  scope :failed, -> { where(status: ['failure', 'error', 'cancelled']) }
  scope :pending, -> { where(status: 'pending') }
  scope :required, -> { where(required: true) }
  
  def self.deduplicate_by_suite
    # Group by suite_name and keep only one check per suite
    grouped = all.group_by(&:suite_name)
    grouped.map { |suite, checks| checks.first }
  end
end

class SupportRotation < ApplicationRecord
  validates :sprint_number, presence: true
  validates :engineer_name, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date

  scope :current, -> { where("start_date <= ? AND end_date >= ?", Date.today, Date.today) }
  scope :for_repository, ->(repo_name, repo_owner) {
    where(repository_name: repo_name, repository_owner: repo_owner)
  }

  def self.current_for_repository(repo_name, repo_owner)
    current.for_repository(repo_name, repo_owner).first
  end

  def self.current_sprint
    current.first
  end

  private

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?

    if end_date < start_date
      errors.add(:end_date, "must be after the start date")
    end
  end
end

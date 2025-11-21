class Api::V1::SprintMetricsController < ApplicationController
  def index
    repository_name = params[:repository_name] || ENV["GITHUB_REPO"]
    repository_owner = params[:repository_owner] || ENV["GITHUB_OWNER"]

    # Get current sprint
    begin
      current_sprint = SupportRotation.current_for_repository(repository_name, repository_owner) ||
                       SupportRotation.current_sprint
    rescue ActiveRecord::StatementInvalid => e
      # Table doesn't exist yet (migration pending)
      Rails.logger.error "SupportRotation table not found: #{e.message}"
      render json: {
        current_sprint: nil,
        daily_approvals: [],
        sprint_totals: {},
        engineer_totals: [],
        error: "Sprint metrics feature not yet configured. Migration pending."
      }, status: :service_unavailable
      return
    end

    # If no sprint data, return empty state
    unless current_sprint
      render json: {
        current_sprint: nil,
        daily_approvals: [],
        sprint_totals: {},
        engineer_totals: []
      }
      return
    end

    # Get daily approvals for the sprint date range
    daily_approvals = calculate_daily_approvals(
      current_sprint.start_date,
      current_sprint.end_date,
      repository_name,
      repository_owner
    )

    # Calculate sprint totals
    sprint_totals = calculate_sprint_totals(
      current_sprint.start_date,
      current_sprint.end_date,
      repository_name,
      repository_owner
    )

    # Get engineer totals
    engineer_totals = calculate_engineer_totals(
      current_sprint.start_date,
      current_sprint.end_date,
      repository_name,
      repository_owner
    )

    render json: {
      current_sprint: {
        sprint_number: current_sprint.sprint_number,
        engineer_name: current_sprint.engineer_name,
        start_date: current_sprint.start_date,
        end_date: current_sprint.end_date,
        repository_name: current_sprint.repository_name,
        repository_owner: current_sprint.repository_owner
      },
      daily_approvals: daily_approvals,
      sprint_totals: sprint_totals,
      engineer_totals: engineer_totals
    }
  end

  def support_rotations
    rotations = SupportRotation.order(start_date: :desc).limit(20)

    render json: rotations
  end

  def create_support_rotation
    rotation = SupportRotation.new(support_rotation_params)

    if rotation.save
      render json: rotation, status: :created
    else
      render json: { errors: rotation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def calculate_daily_approvals(start_date, end_date, repo_name, repo_owner)
    # Get all approvals in the date range for backend team members
    backend_members = BackendReviewGroupMember.pluck(:username)

    reviews = PullRequestReview
      .joins(:pull_request)
      .where(pull_requests: { repository_name: repo_name, repository_owner: repo_owner })
      .where(state: "APPROVED")
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             start_date.beginning_of_day, end_date.end_of_day)
      .where(user: backend_members)

    # Group by date and engineer
    daily_data = reviews.group_by { |r| r.submitted_at.to_date }

    # Build array of daily totals
    (start_date..end_date).map do |date|
      reviews_on_date = daily_data[date] || []
      engineer_breakdown = reviews_on_date.group_by(&:user).transform_values(&:count)

      {
        date: date,
        total: reviews_on_date.count,
        by_engineer: engineer_breakdown
      }
    end
  end

  def calculate_sprint_totals(start_date, end_date, repo_name, repo_owner)
    backend_members = BackendReviewGroupMember.pluck(:username)

    total_approvals = PullRequestReview
      .joins(:pull_request)
      .where(pull_requests: { repository_name: repo_name, repository_owner: repo_owner })
      .where(state: "APPROVED")
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             start_date.beginning_of_day, end_date.end_of_day)
      .where(user: backend_members)
      .count

    days_in_sprint = (end_date - start_date).to_i + 1
    avg_per_day = days_in_sprint > 0 ? (total_approvals.to_f / days_in_sprint).round(1) : 0

    {
      total: total_approvals,
      days: days_in_sprint,
      average_per_day: avg_per_day
    }
  end

  def calculate_engineer_totals(start_date, end_date, repo_name, repo_owner)
    backend_members = BackendReviewGroupMember.pluck(:username)

    reviews = PullRequestReview
      .joins(:pull_request)
      .where(pull_requests: { repository_name: repo_name, repository_owner: repo_owner })
      .where(state: "APPROVED")
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             start_date.beginning_of_day, end_date.end_of_day)
      .where(user: backend_members)

    # Group by engineer
    engineer_counts = reviews.group(:user).count

    # Convert to array of hashes and sort
    engineer_counts.map do |engineer, count|
      {
        engineer: engineer,
        approvals: count
      }
    end.sort_by { |e| -e[:approvals] }
  end

  def support_rotation_params
    params.require(:support_rotation).permit(
      :sprint_number,
      :engineer_name,
      :start_date,
      :end_date,
      :repository_name,
      :repository_owner
    )
  end
end

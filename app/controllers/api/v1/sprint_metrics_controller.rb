class Api::V1::SprintMetricsController < ApplicationController
  def index
    repository_name = params[:repository_name] || ENV["GITHUB_REPO"]
    repository_owner = params[:repository_owner] || ENV["GITHUB_OWNER"]
    sprint_offset = (params[:sprint_offset] || 0).to_i

    # Get sprint (current or offset)
    begin
      if sprint_offset == 0
        current_sprint = SupportRotation.current_for_repository(repository_name, repository_owner) ||
                         SupportRotation.current_sprint
      else
        # Get sprint by offset (negative for past sprints)
        current_sprint = SupportRotation
          .where(repository_name: repository_name, repository_owner: repository_owner)
          .order(start_date: :desc)
          .offset(-sprint_offset) # Convert negative offset to positive for SQL
          .first
      end
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

    # Get approved PRs grouped by day
    approved_prs_by_day = get_approved_prs_by_day(
      current_sprint.start_date,
      current_sprint.end_date,
      repository_name,
      repository_owner
    )

    # Get dependabot metrics
    dependabot_metrics = calculate_dependabot_metrics(
      current_sprint.start_date,
      current_sprint.end_date,
      repository_name,
      repository_owner
    )

    # Get approved-but-unmerged PRs count
    approved_unmerged_count = count_approved_unmerged_prs(
      current_sprint.start_date,
      current_sprint.end_date,
      repository_name,
      repository_owner
    )

    # Get upcoming rotations (next 2)
    upcoming_rotations = SupportRotation
      .where("start_date > ?", current_sprint.end_date)
      .order(start_date: :asc)
      .limit(2)
      .map do |rotation|
        {
          engineer_name: rotation.engineer_name,
          start_date: rotation.start_date,
          end_date: rotation.end_date
        }
      end

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
      engineer_totals: engineer_totals,
      approved_prs_by_day: approved_prs_by_day,
      dependabot_metrics: dependabot_metrics,
      approved_unmerged_count: approved_unmerged_count,
      upcoming_rotations: upcoming_rotations
    }
  end

  def detailed
    repository_name = params[:repository_name] || ENV["GITHUB_REPO"]
    repository_owner = params[:repository_owner] || ENV["GITHUB_OWNER"]
    sprint_offset = (params[:sprint_offset] || 0).to_i

    # Get current sprint
    current_sprint = if sprint_offset == 0
      SupportRotation.current_for_repository(repository_name, repository_owner) ||
        SupportRotation.current_sprint
    else
      SupportRotation
        .where(repository_name: repository_name, repository_owner: repository_owner)
        .order(start_date: :desc)
        .offset(-sprint_offset)
        .first
    end

    unless current_sprint
      render json: { error: "No sprint data found" }, status: :not_found
      return
    end

    # Calculate detailed metrics
    metrics = {
      sprint_info: {
        sprint_number: current_sprint.sprint_number,
        engineer_name: current_sprint.engineer_name,
        start_date: current_sprint.start_date,
        end_date: current_sprint.end_date
      },
      time_to_approval: calculate_time_to_approval(current_sprint.start_date, current_sprint.end_date, repository_name, repository_owner),
      first_response_time: calculate_first_response_time(current_sprint.start_date, current_sprint.end_date, repository_name, repository_owner),
      review_cycles: calculate_review_cycles(current_sprint.start_date, current_sprint.end_date, repository_name, repository_owner),
      approval_rate: calculate_approval_rate(current_sprint.start_date, current_sprint.end_date, repository_name, repository_owner),
      stale_prs: calculate_stale_prs(current_sprint.start_date, current_sprint.end_date, repository_name, repository_owner),
      repository_breakdown: calculate_repository_breakdown(current_sprint.start_date, current_sprint.end_date),
      sprint_comparison: calculate_sprint_comparison(current_sprint, repository_name, repository_owner),
      queue_depth_over_time: calculate_queue_depth_over_time(current_sprint.start_date, current_sprint.end_date, repository_name, repository_owner)
    }

    render json: metrics
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
    # Query across ALL repositories, not just the sprint's primary repo
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Use EST timezone for date calculations
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    reviews = PullRequestReview
      .joins(:pull_request)
      .where(state: "APPROVED")
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)
      .where(user: backend_members)

    # Group by date in EST timezone
    daily_data = reviews.group_by { |r| r.submitted_at.in_time_zone(est_zone).to_date }

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
    # Query across ALL repositories
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Use EST timezone
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    total_approvals = PullRequestReview
      .joins(:pull_request)
      .where(state: "APPROVED")
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)
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
    # Query across ALL repositories
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Use EST timezone
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    reviews = PullRequestReview
      .joins(:pull_request)
      .where(state: "APPROVED")
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)
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

  def get_approved_prs_by_day(start_date, end_date, repo_name, repo_owner)
    # Query across ALL repositories
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Use EST timezone
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    # Get all approved reviews in the date range across all repositories
    reviews = PullRequestReview
      .joins(:pull_request)
      .where(state: "APPROVED")
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)
      .where(user: backend_members)
      .includes(:pull_request)
      .order(:submitted_at)

    # Group by date in EST timezone
    grouped_by_date = reviews.group_by { |r| r.submitted_at.in_time_zone(est_zone).to_date }

    # Build the response
    (start_date..end_date).map do |date|
      reviews_on_date = grouped_by_date[date] || []

      prs_on_date = reviews_on_date.map do |review|
        pr = review.pull_request
        {
          number: pr.number,
          title: pr.title,
          url: pr.url,
          author: pr.author,
          approved_by: review.user,
          approved_at: review.submitted_at,
          state: pr.state
        }
      end

      {
        date: date,
        prs: prs_on_date
      }
    end.reject { |day| day[:prs].empty? } # Only include days with PRs
  end

  # Detailed metrics calculation methods
  def calculate_time_to_approval(start_date, end_date, repo_name, repo_owner)
    backend_members = BackendReviewGroupMember.pluck(:username)
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    # Get PRs that were approved during the sprint
    prs = PullRequest
      .joins(:pull_request_reviews)
      .where(pull_request_reviews: { state: "APPROVED", user: backend_members })
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)
      .distinct

    times = []
    prs.each do |pr|
      # Find when it became ready for review (first non-draft state or first approval request)
      ready_time = pr.pr_created_at

      # Find first backend approval
      first_approval = pr.pull_request_reviews
        .where(state: "APPROVED", user: backend_members)
        .order(:submitted_at)
        .first

      if first_approval && ready_time
        hours = ((first_approval.submitted_at - ready_time) / 1.hour).round(1)
        times << { pr_number: pr.number, hours: hours, days: (hours / 24.0).round(1) }
      end
    end

    {
      average_hours: times.any? ? (times.sum { |t| t[:hours] } / times.count).round(1) : 0,
      average_days: times.any? ? (times.sum { |t| t[:days] } / times.count).round(1) : 0,
      median_hours: times.any? ? times.map { |t| t[:hours] }.sort[times.count / 2].round(1) : 0,
      sample_size: times.count,
      distribution: times.sort_by { |t| -t[:hours] }.first(10)
    }
  end

  def calculate_first_response_time(start_date, end_date, repo_name, repo_owner)
    backend_members = BackendReviewGroupMember.pluck(:username)
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    prs = PullRequest
      .where("pr_created_at >= ? AND pr_created_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)

    times = []
    prs.each do |pr|
      first_review = pr.pull_request_reviews
        .where(user: backend_members)
        .order(:submitted_at)
        .first

      if first_review
        hours = ((first_review.submitted_at - pr.pr_created_at) / 1.hour).round(1)
        times << { pr_number: pr.number, hours: hours, reviewer: first_review.user }
      end
    end

    {
      average_hours: times.any? ? (times.sum { |t| t[:hours] } / times.count).round(1) : 0,
      median_hours: times.any? ? times.map { |t| t[:hours] }.sort[times.count / 2].round(1) : 0,
      sample_size: times.count,
      fastest_reviewers: times.group_by { |t| t[:reviewer] }
        .transform_values { |v| (v.sum { |t| t[:hours] } / v.count).round(1) }
        .sort_by { |k, v| v }
        .first(5)
        .to_h
    }
  end

  def calculate_review_cycles(start_date, end_date, repo_name, repo_owner)
    backend_members = BackendReviewGroupMember.pluck(:username)
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    prs = PullRequest
      .joins(:pull_request_reviews)
      .where(pull_request_reviews: { user: backend_members })
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)
      .distinct

    cycles_data = []
    prs.each do |pr|
      changes_requested_count = pr.pull_request_reviews
        .where(state: "CHANGES_REQUESTED", user: backend_members)
        .count

      approved_count = pr.pull_request_reviews
        .where(state: "APPROVED", user: backend_members)
        .count

      if approved_count > 0
        cycles_data << {
          pr_number: pr.number,
          cycles: changes_requested_count + 1,
          approved: approved_count > 0
        }
      end
    end

    {
      average_cycles: cycles_data.any? ? (cycles_data.sum { |c| c[:cycles] } / cycles_data.count.to_f).round(1) : 0,
      first_time_approval_rate: cycles_data.count { |c| c[:cycles] == 1 }.to_f / [cycles_data.count, 1].max * 100,
      distribution: cycles_data.group_by { |c| c[:cycles] }.transform_values(&:count).sort.to_h,
      sample_size: cycles_data.count
    }
  end

  def calculate_approval_rate(start_date, end_date, repo_name, repo_owner)
    backend_members = BackendReviewGroupMember.pluck(:username)
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    total_reviewed = PullRequest
      .joins(:pull_request_reviews)
      .where(pull_request_reviews: { user: backend_members })
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)
      .distinct
      .count

    approved_first_time = PullRequest
      .joins(:pull_request_reviews)
      .where(pull_request_reviews: { user: backend_members, state: "APPROVED" })
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)
      .where.not(id: PullRequest
        .joins(:pull_request_reviews)
        .where(pull_request_reviews: { user: backend_members, state: "CHANGES_REQUESTED" })
        .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
               est_zone.parse(start_date.to_s).beginning_of_day.utc,
               est_zone.parse(end_date.to_s).end_of_day.utc)
        .select(:id))
      .distinct
      .count

    {
      first_time_approval_rate: total_reviewed > 0 ? (approved_first_time.to_f / total_reviewed * 100).round(1) : 0,
      total_reviewed: total_reviewed,
      approved_first_time: approved_first_time,
      required_changes: total_reviewed - approved_first_time
    }
  end

  def calculate_stale_prs(start_date, end_date, repo_name, repo_owner)
    stale_threshold_days = 7
    now = Time.current

    stale_prs = PullRequest
      .where(state: "open")
      .where("pr_created_at < ?", now - stale_threshold_days.days)
      .where(backend_approval_status: [ "pending", nil ])
      .order(pr_created_at: :asc)
      .limit(20)
      .map do |pr|
        days_old = ((now - pr.pr_created_at) / 1.day).round
        {
          number: pr.number,
          title: pr.title,
          author: pr.author,
          days_old: days_old,
          url: pr.url
        }
      end

    {
      count: stale_prs.count,
      threshold_days: stale_threshold_days,
      prs: stale_prs
    }
  end

  def calculate_repository_breakdown(start_date, end_date)
    backend_members = BackendReviewGroupMember.pluck(:username)
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    reviews = PullRequestReview
      .joins(:pull_request)
      .where(state: "APPROVED", user: backend_members)
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)

    breakdown = reviews
      .group("pull_requests.repository_name")
      .count
      .sort_by { |k, v| -v }
      .map { |repo, count| { repository: repo, reviews: count } }

    {
      repositories: breakdown,
      total_repositories: breakdown.count
    }
  end

  def calculate_sprint_comparison(current_sprint, repo_name, repo_owner)
    # Get last 6 sprints (3 months)
    sprints = SupportRotation
      .where(repository_name: repo_name, repository_owner: repo_owner)
      .where("end_date <= ?", current_sprint.end_date)
      .order(start_date: :desc)
      .limit(6)
      .reverse

    backend_members = BackendReviewGroupMember.pluck(:username)
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    comparison = sprints.map do |sprint|
      approvals = PullRequestReview
        .joins(:pull_request)
        .where(state: "APPROVED", user: backend_members)
        .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
               est_zone.parse(sprint.start_date.to_s).beginning_of_day.utc,
               est_zone.parse(sprint.end_date.to_s).end_of_day.utc)
        .count

      business_days = calculate_business_days_count(sprint.start_date, sprint.end_date)
      avg_per_day = business_days > 0 ? (approvals.to_f / business_days).round(1) : 0

      {
        sprint_number: sprint.sprint_number,
        engineer: sprint.engineer_name,
        start_date: sprint.start_date,
        end_date: sprint.end_date,
        total_approvals: approvals,
        business_days: business_days,
        avg_per_day: avg_per_day
      }
    end

    {
      sprints: comparison,
      trend: calculate_trend(comparison.map { |s| s[:avg_per_day] })
    }
  end

  def calculate_queue_depth_over_time(start_date, end_date, repo_name, repo_owner)
    backend_members = BackendReviewGroupMember.pluck(:username)
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    daily_queue = (start_date..end_date).map do |date|
      # Count PRs that were waiting for review on this date
      waiting_count = PullRequest
        .where(state: "open")
        .where("pr_created_at <= ?", est_zone.parse(date.to_s).end_of_day.utc)
        .where(backend_approval_status: [ "pending", nil ])
        .count

      {
        date: date,
        queue_depth: waiting_count
      }
    end

    {
      daily_data: daily_queue,
      max_depth: daily_queue.map { |d| d[:queue_depth] }.max || 0,
      avg_depth: daily_queue.any? ? (daily_queue.sum { |d| d[:queue_depth] } / daily_queue.count.to_f).round(1) : 0
    }
  end

  def calculate_business_days_count(start_date, end_date)
    count = 0
    current = start_date
    while current <= end_date
      count += 1 unless current.wday == 0 || current.wday == 6
      current += 1.day
    end
    count
  end

  def calculate_trend(values)
    return "stable" if values.count < 2

    recent_avg = values.last(2).sum / 2.0
    older_avg = values.first([values.count - 2, 1].max).sum / [values.count - 2, 1].max.to_f

    diff_pct = ((recent_avg - older_avg) / [older_avg, 1].max * 100).round(1)

    if diff_pct > 10
      "increasing"
    elsif diff_pct < -10
      "decreasing"
    else
      "stable"
    end
  end

  def calculate_dependabot_metrics(start_date, end_date, repo_name, repo_owner)
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    # Find all dependabot PRs that were updated during the sprint
    # We look for PRs where the author is dependabot[bot] or dependabot
    dependabot_authors = [ "dependabot[bot]", "dependabot" ]

    # PRs merged during the sprint
    merged_prs = PullRequest
      .where(author: dependabot_authors)
      .where(state: "merged")
      .where("pr_updated_at >= ? AND pr_updated_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)

    # PRs closed (but not merged) during the sprint
    closed_prs = PullRequest
      .where(author: dependabot_authors)
      .where(state: "closed")
      .where("pr_updated_at >= ? AND pr_updated_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)

    {
      merged_count: merged_prs.count,
      closed_count: closed_prs.count,
      merged_prs: merged_prs.limit(20).map do |pr|
        {
          number: pr.number,
          title: pr.title,
          url: pr.url,
          repository: pr.repository_name
        }
      end,
      closed_prs: closed_prs.limit(20).map do |pr|
        {
          number: pr.number,
          title: pr.title,
          url: pr.url,
          repository: pr.repository_name
        }
      end
    }
  end

  def count_approved_unmerged_prs(start_date, end_date, repo_name, repo_owner)
    backend_members = BackendReviewGroupMember.pluck(:username)
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    # Find PRs that were approved during the sprint but are still open (not merged yet)
    approved_unmerged = PullRequest
      .joins(:pull_request_reviews)
      .where(pull_request_reviews: { state: "APPROVED", user: backend_members })
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)
      .where(state: "open")
      .distinct
      .count

    approved_unmerged
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

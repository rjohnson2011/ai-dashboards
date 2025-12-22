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
        # Get sprint by offset relative to current sprint
        # First find the current sprint
        base_sprint = SupportRotation.current_for_repository(repository_name, repository_owner) ||
                      SupportRotation.current_sprint

        if base_sprint
          if sprint_offset < 0
            # Negative offset = go to PAST sprints (earlier end dates)
            # Order by end_date descending (newest first), find sprints that ended before current
            current_sprint = SupportRotation
              .where(repository_name: repository_name, repository_owner: repository_owner)
              .where("end_date < ?", base_sprint.start_date)
              .order(end_date: :desc)
              .offset(-sprint_offset - 1) # offset -1 means first sprint before current
              .first
          else
            # Positive offset = go to FUTURE sprints (later start dates)
            # Order by start_date ascending (oldest first), find sprints that start after current
            current_sprint = SupportRotation
              .where(repository_name: repository_name, repository_owner: repository_owner)
              .where("start_date > ?", base_sprint.end_date)
              .order(start_date: :asc)
              .offset(sprint_offset - 1) # offset 1 means first sprint after current
              .first
          end
        else
          # No current sprint found, fall back to absolute positioning
          current_sprint = SupportRotation
            .where(repository_name: repository_name, repository_owner: repository_owner)
            .order(start_date: :desc)
            .offset(-sprint_offset)
            .first
        end
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

    # Get backend-approved and closed PRs for past 6 months
    backend_approved_closed = calculate_backend_approved_closed_prs(
      repository_name,
      repository_owner
    )

    # Check if there are previous/next sprints available for navigation
    has_previous_sprint = SupportRotation
      .where(repository_name: repository_name, repository_owner: repository_owner)
      .where("end_date < ?", current_sprint.start_date)
      .exists?

    has_next_sprint = SupportRotation
      .where(repository_name: repository_name, repository_owner: repository_owner)
      .where("start_date > ?", current_sprint.end_date)
      .exists?

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
      upcoming_rotations: upcoming_rotations,
      backend_approved_closed: backend_approved_closed,
      has_previous_sprint: has_previous_sprint,
      has_next_sprint: has_next_sprint
    }
  end

  def detailed
    repository_name = params[:repository_name] || ENV["GITHUB_REPO"]
    repository_owner = params[:repository_owner] || ENV["GITHUB_OWNER"]
    sprint_offset = (params[:sprint_offset] || 0).to_i

    # Get current sprint (using same logic as index method)
    current_sprint = if sprint_offset == 0
      SupportRotation.current_for_repository(repository_name, repository_owner) ||
        SupportRotation.current_sprint
    else
      # Get sprint by offset relative to current sprint
      base_sprint = SupportRotation.current_for_repository(repository_name, repository_owner) ||
                    SupportRotation.current_sprint

      if base_sprint
        if sprint_offset < 0
          # Negative offset = go to PAST sprints (earlier end dates)
          SupportRotation
            .where(repository_name: repository_name, repository_owner: repository_owner)
            .where("end_date < ?", base_sprint.start_date)
            .order(end_date: :desc)
            .offset(-sprint_offset - 1)
            .first
        else
          # Positive offset = go to FUTURE sprints (later start dates)
          SupportRotation
            .where(repository_name: repository_name, repository_owner: repository_owner)
            .where("start_date > ?", base_sprint.end_date)
            .order(start_date: :asc)
            .offset(sprint_offset - 1)
            .first
        end
      else
        # No current sprint found, fall back to absolute positioning
        SupportRotation
          .where(repository_name: repository_name, repository_owner: repository_owner)
          .order(start_date: :desc)
          .offset(-sprint_offset)
          .first
      end
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

    # Build array of daily totals by querying each day separately
    (start_date..end_date).map do |date|
      # Query only approvals for this specific date
      reviews_on_date = PullRequestReview
        .joins(:pull_request)
        .where(state: "APPROVED")
        .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at < ?",
               est_zone.parse(date.to_s).beginning_of_day.utc,
               est_zone.parse(date.to_s).end_of_day.utc)
        .where(user: backend_members)
        .select(:user, :pull_request_id)

      # Count unique PRs per engineer (same PR approved by multiple engineers = 1 per engineer)
      engineer_breakdown = {}
      reviews_on_date.group_by(&:user).each do |engineer, engineer_reviews|
        unique_pr_ids = engineer_reviews.map(&:pull_request_id).uniq
        engineer_breakdown[engineer] = unique_pr_ids.count
      end

      # Total = unique PRs that received backend approval on this date
      unique_pr_ids_for_day = reviews_on_date.map(&:pull_request_id).uniq

      {
        date: date,
        total: unique_pr_ids_for_day.count,
        by_engineer: engineer_breakdown
      }
    end
  end

  def calculate_sprint_totals(start_date, end_date, repo_name, repo_owner)
    # Query across ALL repositories
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Use EST timezone
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    # Count unique PRs that received backend approvals (not total approval actions)
    total_approvals = PullRequestReview
      .joins(:pull_request)
      .where(state: "APPROVED")
      .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
             est_zone.parse(start_date.to_s).beginning_of_day.utc,
             est_zone.parse(end_date.to_s).end_of_day.utc)
      .where(user: backend_members)
      .select("DISTINCT pull_requests.id")
      .count

    # Count BUSINESS DAYS ONLY (Monday-Friday, excluding weekends)
    business_days_in_sprint = count_business_days(start_date, end_date)

    # Calculate business days elapsed (from start to today, capped at total sprint business days)
    today = est_zone.now.to_date
    business_days_elapsed = count_business_days(start_date, [ today, end_date ].min)
    business_days_elapsed = [ business_days_elapsed, 1 ].max # At least 1 day

    # Use business days elapsed for average calculation
    avg_per_day = business_days_elapsed > 0 ? (total_approvals.to_f / business_days_elapsed).round(1) : 0

    {
      total: total_approvals,
      days: business_days_in_sprint,
      days_elapsed: business_days_elapsed,
      average_per_day: avg_per_day
    }
  end

  def calculate_engineer_totals(start_date, end_date, repo_name, repo_owner)
    # Query across ALL repositories
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Use EST timezone
    est_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

    # Count unique PRs approved by each engineer (not total approval actions)
    # This prevents double-counting when multiple engineers approve the same PR
    engineer_counts = {}

    backend_members.each do |engineer|
      unique_prs_count = PullRequestReview
        .joins(:pull_request)
        .where(state: "APPROVED")
        .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at <= ?",
               est_zone.parse(start_date.to_s).beginning_of_day.utc,
               est_zone.parse(end_date.to_s).end_of_day.utc)
        .where(user: engineer)
        .select("DISTINCT pull_requests.id")
        .count

      engineer_counts[engineer] = unique_prs_count if unique_prs_count > 0
    end

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

    # Build the response by querying each day separately to avoid loading all into memory
    (start_date..end_date).map do |date|
      # Query only reviews for this specific date
      reviews_on_date = PullRequestReview
        .joins(:pull_request)
        .where(state: "APPROVED")
        .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at < ?",
               est_zone.parse(date.to_s).beginning_of_day.utc,
               est_zone.parse(date.to_s).end_of_day.utc)
        .where(user: backend_members)
        .select("pull_request_reviews.*, pull_requests.number, pull_requests.title, pull_requests.url, pull_requests.author, pull_requests.state")
        .order("pull_request_reviews.submitted_at")

      # Group reviews by PR using database query
      pr_reviews = reviews_on_date.group_by(&:pull_request_id)

      prs_on_date = pr_reviews.map do |pr_id, reviews|
        # Use the first approval for this PR on this day
        review = reviews.first

        # Get all approvers for this PR on this day
        approvers = reviews.map(&:user).uniq

        {
          number: review.number,
          title: review.title,
          url: review.url,
          author: review.author,
          approved_by: approvers.join(", "),
          approved_at: review.submitted_at,
          state: review.state
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
      first_time_approval_rate: cycles_data.count { |c| c[:cycles] == 1 }.to_f / [ cycles_data.count, 1 ].max * 100,
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
    older_avg = values.first([ values.count - 2, 1 ].max).sum / [ values.count - 2, 1 ].max.to_f

    diff_pct = ((recent_avg - older_avg) / [ older_avg, 1 ].max * 100).round(1)

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

  def calculate_backend_approved_closed_prs(repo_name, repo_owner)
    # Cache key includes repo, date, and version to bust stale cache
    # Increment version when calculation logic changes
    cache_version = "v3" # Incremented due to query logic change
    cache_key = "backend_approved_closed_prs:#{cache_version}:#{repo_owner}:#{repo_name}:#{Date.today}"

    # Cache for 24 hours - historical data doesn't change, only need to add today's PRs
    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      backend_members = BackendReviewGroupMember.pluck(:username)
      six_months_ago = 6.months.ago

      # FIXED: Count PRs by when they received backend approval (review submission date)
      # Previously used PR's approved_at/updated_at which was incorrect
      # Now groups by the actual review submission timestamp

      # Build subquery to get first backend approval for each PR
      # This uses raw SQL since ActiveRecord can't handle DISTINCT ON with GROUP BY well
      # Use connection.quote to prevent SQL injection
      conn = ActiveRecord::Base.connection
      quoted_members = backend_members.map { |m| conn.quote(m) }.join(",")
      quoted_repo_name = conn.quote(repo_name)
      quoted_repo_owner = conn.quote(repo_owner)
      quoted_date = conn.quote(six_months_ago.iso8601)

      subquery = <<-SQL
        SELECT DISTINCT ON (pr.id)
          pr.id,
          pr.state,
          pr_reviews.submitted_at as approval_date
        FROM pull_requests pr
        INNER JOIN pull_request_reviews pr_reviews ON pr_reviews.pull_request_id = pr.id
        WHERE pr_reviews.state = 'APPROVED'
          AND pr_reviews.user IN (#{quoted_members})
          AND pr.state IN ('closed', 'merged')
          AND pr.repository_name = #{quoted_repo_name}
          AND pr.repository_owner = #{quoted_repo_owner}
          AND pr_reviews.submitted_at >= #{quoted_date}
        ORDER BY pr.id, pr_reviews.submitted_at ASC
      SQL

      # Use the subquery to count by month
      monthly_query = <<-SQL
        SELECT
          DATE_TRUNC('month', approval_date) as month,
          state,
          COUNT(*) as count
        FROM (#{subquery}) as approved_prs
        GROUP BY DATE_TRUNC('month', approval_date), state
      SQL

      # brakeman:ignore:SQL
      monthly_results = ActiveRecord::Base.connection.execute(monthly_query)

      # Convert results to hash format
      monthly_counts = {}
      monthly_results.each do |row|
        # row['month'] is already a Time object from PostgreSQL
        month_time = row["month"].is_a?(Time) ? row["month"] : Time.parse(row["month"])
        month_key = [ month_time, row["state"] ]
        monthly_counts[month_key] = row["count"].to_i
      end

      # Get total counts
      total_query = "SELECT COUNT(*) as count, state FROM (#{subquery}) as approved_prs GROUP BY state"
      # brakeman:ignore:SQL
      total_results = ActiveRecord::Base.connection.execute(total_query)

      merged_count = total_results.find { |r| r["state"] == "merged" }&.fetch("count", 0)&.to_i || 0
      closed_count = total_results.find { |r| r["state"] == "closed" }&.fetch("count", 0)&.to_i || 0
      total_count = merged_count + closed_count

      # Build monthly breakdown from aggregated counts
      monthly_breakdown = monthly_counts.group_by { |(month_timestamp, _state), _count| month_timestamp }.map do |month_timestamp, group|
        month_date = month_timestamp.to_date
        merged = group.find { |(_, state), _| state == "merged" }&.last || 0
        closed = group.find { |(_, state), _| state == "closed" }&.last || 0

        # Fetch sample PRs approved in this month (first backend approval in this month)
        sample_prs = PullRequest
          .select("pull_requests.*, MIN(pull_request_reviews.submitted_at) as first_backend_approval")
          .joins(:pull_request_reviews)
          .where(pull_request_reviews: { state: "APPROVED", user: backend_members })
          .where(state: [ "closed", "merged" ])
          .where("pull_request_reviews.submitted_at >= ? AND pull_request_reviews.submitted_at < ?",
                 month_timestamp,
                 month_timestamp + 1.month)
          .where(repository_name: repo_name, repository_owner: repo_owner)
          .group("pull_requests.id")
          .limit(5)
          .map do |pr|
            {
              number: pr.number,
              title: pr.title,
              url: pr.url,
              state: pr.state,
              author: pr.author,
              closed_at: pr.first_backend_approval,
              approved_by: [] # Omit approvers to save queries
            }
          end

        {
          month: month_date.strftime("%B %Y"),
          month_date: month_date,
          total: merged + closed,
          merged: merged,
          closed: closed,
          prs: sample_prs
        }
      end.sort_by { |m| m[:month_date] }.reverse

      {
        total: total_count,
        merged: merged_count,
        closed: closed_count,
        monthly_breakdown: monthly_breakdown
      }
    end
  end

  # Count business days (Monday-Friday) between two dates, inclusive
  def count_business_days(start_date, end_date)
    # Ensure start_date is before or equal to end_date
    return 0 if start_date > end_date

    count = 0
    current_date = start_date

    while current_date <= end_date
      # Count only weekdays (Monday=1, Tuesday=2, ..., Friday=5)
      # Saturday=6, Sunday=0
      count += 1 unless [ 0, 6 ].include?(current_date.wday)
      current_date += 1.day
    end

    count
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

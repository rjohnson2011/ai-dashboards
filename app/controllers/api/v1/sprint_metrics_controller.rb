class Api::V1::SprintMetricsController < ApplicationController
  # Approvals per reviewer over fixed windows. Replaces the sprint/rotation
  # view — the team no longer runs sprints. APPROVED only, by team decision;
  # see ReviewEvent::COUNTED_STATE.
  def reviewer_activity
    repository_name = params[:repository_name].presence
    backend_members = BackendReviewGroupMember.cached_usernames
    reviewers = params[:backend_only] == "true" ? backend_members : nil

    windows = {
      day: 1.day.ago,
      week: 7.days.ago,
      month: 30.days.ago,
      ytd: Time.zone.local(2026, 1, 1)
    }

    # Three parallel scopes so the page can chart human-authored PRs,
    # dependabot PRs, and combined totals side by side.
    scopes = { all: :all, human: :exclude, dependabot: :only }
    payload = scopes.transform_values do |dependabot_scope|
      windows.transform_values do |since|
        ReviewEvent.counts_since(since, repository_name: repository_name,
                                        reviewers: reviewers, dependabot: dependabot_scope)
          .sort_by { |_r, count| -count }
          .map { |reviewer, count| { reviewer: reviewer, count: count } }
      end
    end

    # `windows` kept for any consumer of the old shape (combined scope).
    render json: { scopes: payload, windows: payload[:all], backend_members: backend_members, generated_at: Time.current }
  rescue StandardError => e
    Rails.logger.error "[SprintMetrics] reviewer_activity failed: #{e.class}: #{e.message}"
    render json: { error: "Failed to load reviewer activity" }, status: :internal_server_error
  end

  private
end

# Durable, insert-only record of every review we have ever observed.
#
# pull_request_reviews cannot serve this purpose: it is destroy_all'd and
# rewritten on every scrape, and merged PRs are deleted entirely by the
# scraper's cleanup step. No foreign key to pull_requests for exactly that
# reason: the event must outlive the PR row.
class ReviewEvent < ApplicationRecord
  # Per team decision (2026-08-20), only an APPROVED review counts toward a
  # reviewer's totals. CHANGES_REQUESTED/COMMENTED rows are still stored —
  # storage is cheap and the decision stays reversible — but never counted.
  COUNTED_STATE = "APPROVED"

  scope :counted, -> { where(state: COUNTED_STATE) }

  # Approvals per reviewer since `time`. `reviewers:` narrows to a given list
  # (used for the backend-review-group filter). Plain hash out — no relations
  # leaking into the JSON layer.
  def self.counts_since(time, repository_name: nil, reviewers: nil)
    scope = counted.where("submitted_at >= ?", time)
    scope = scope.where(repository_name: repository_name) if repository_name.present?
    scope = scope.where(reviewer: reviewers) if reviewers.present?
    scope.group(:reviewer).count
  end

  # Idempotent bulk write: re-recording the same review is a no-op because
  # github_ids are stable (REST integer IDs, or SHA256-hashed GraphQL node IDs
  # — see GithubService#graphql_reviews).
  def self.record_all(rows)
    return 0 if rows.blank?

    now = Time.current
    stamped = rows.map { |r| r.merge(created_at: now, updated_at: now) }
    # upsert (not insert): re-running the backfill must be able to fill
    # pr_author onto rows recorded before the column existed. Only that column
    # updates on conflict, so counts/timestamps can never be rewritten.
    result = upsert_all(stamped, unique_by: :github_id, update_only: %i[pr_author])
    result.count
  end
end

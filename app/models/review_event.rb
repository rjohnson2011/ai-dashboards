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
  # GHE reports this author differently per API: REST returns "dependabot[bot]"
  # (what the scraper stamps), GraphQL returns "dependabot" (what the backfill
  # stamps). Match both, or merged dependabot PRs — recorded only by the
  # backfill — silently count as human-authored.
  DEPENDABOT_AUTHORS = [ "dependabot[bot]", "dependabot" ].freeze

  # Approvals per reviewer since `time`.
  # dependabot: :all (default) counts everything; :exclude drops approvals on
  # dependabot-authored PRs; :only counts nothing else. NULL pr_author (rows
  # predating the column) is treated as human-authored.
  def self.counts_since(time, repository_name: nil, reviewers: nil, dependabot: :all)
    scope = counted.where("submitted_at >= ?", time)
    scope = scope.where(repository_name: repository_name) if repository_name.present?
    scope = scope.where(reviewer: reviewers) if reviewers.present?
    case dependabot
    when :exclude
      scope = scope.where("pr_author IS NULL OR pr_author NOT IN (?)", DEPENDABOT_AUTHORS)
    when :only
      scope = scope.where(pr_author: DEPENDABOT_AUTHORS)
    end
    scope.group(:reviewer).count
  end

  # Every counted approval since `time`, oldest first, as plain hashes ready
  # for JSON. Feeds the analytics page's time-series charts, which need the
  # individual timestamps rather than the per-window totals above. Same
  # reviewer/repository narrowing as counts_since so the charts and the
  # leaderboard always describe the same slice.
  # Each event carries the PR's web link (buildable from owner/repo/number
  # alone) and its title when the PR row still exists — merged PRs are
  # deleted by the scraper's cleanup, so the title is best-effort.
  def self.recent_approvals(time, repository_name: nil, reviewers: nil)
    scope = counted.where("submitted_at >= ?", time)
    scope = scope.where(repository_name: repository_name) if repository_name.present?
    scope = scope.where(reviewer: reviewers) if reviewers.present?
    rows = scope.order(:submitted_at, :id)
                .pluck(:reviewer, :submitted_at, :pr_author, :pr_number, :repository_name, :repository_owner)
    titles = pr_titles_for(rows.map { |r| [ r[5], r[4], r[3] ] }.uniq)
    rows.map do |reviewer, at, author, pr, repo, owner|
      {
        reviewer: reviewer, at: at.iso8601, dependabot: DEPENDABOT_AUTHORS.include?(author),
        pr: pr, repo: repo, title: titles[[ owner, repo, pr ]],
        url: "#{Octokit.web_endpoint.to_s.chomp('/')}/#{owner}/#{repo}/pull/#{pr}"
      }
    end
  end

  # { [owner, repo, number] => title } for the PRs we still hold a row for.
  def self.pr_titles_for(keys)
    return {} if keys.empty?

    numbers = keys.map(&:last).compact.uniq
    PullRequest.where(number: numbers)
                .pluck(:repository_owner, :repository_name, :number, :title)
                .each_with_object({}) { |(owner, repo, number, title), h| h[[ owner, repo, number ]] = title }
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

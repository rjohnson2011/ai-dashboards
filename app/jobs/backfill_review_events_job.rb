# Backfill/reconciliation for review_events via batched GraphQL.
#
# One call fetches 25 merged PRs with their reviews nested, so a full year
# (~4,000 PRs) costs ~160 calls — versus ~4,000 for the REST equivalent.
# Run once with since: Time.utc(2026, 1, 1) to backfill 2026, and daily with a
# small window (the workflow passes since: 3.days.ago) as a safety net for
# reviews the 15-minute scraper missed (e.g. approval seconds before merge).
#
# Idempotent: ReviewEvent.record_all ignores github_ids it has seen, and the
# node-ID hashing below matches GithubService#graphql_reviews exactly.
class BackfillReviewEventsJob < ApplicationJob
  queue_as :default

  PAGE_SIZE = 25
  # Hard stop against runaway pagination. Sized from observation, not guess:
  # the 2026 backfill hit a 250-page cap at exactly 6,250 PRs without reaching
  # Jan 1 — "updated since" includes closed PRs touched for any reason, which
  # far outnumbers PRs merged in the window. 600 pages ≈ 15,000 PRs / 600 API
  # calls, comfortably covering a year while still bounding a runaway.
  MAX_PAGES = 600

  def perform(since:, repository_name: nil, repository_owner: nil)
    repo = repository_name || ENV["GITHUB_REPO"]
    owner = repository_owner || ENV["GITHUB_OWNER"]
    client = Octokit::Client.new(access_token: ENV["GITHUB_TOKEN"], api_endpoint: ENV.fetch("GITHUB_API_ENDPOINT", "https://api.va.ghe.com"))

    prs_scanned = 0
    events_recorded = 0
    api_calls = 0
    cursor = nil

    MAX_PAGES.times do
      query = <<~GRAPHQL
        query {
          repository(owner: "#{owner}", name: "#{repo}") {
            pullRequests(first: #{PAGE_SIZE}, states: [MERGED], orderBy: {field: UPDATED_AT, direction: DESC}#{cursor ? ", after: \"#{cursor}\"" : ""}) {
              pageInfo { hasNextPage endCursor }
              nodes {
                number
                updatedAt
                reviews(first: 50) {
                  nodes { id state submittedAt author { login } }
                }
              }
            }
          }
        }
      GRAPHQL

      response = client.post("/graphql", { query: query }.to_json)
      api_calls += 1
      page = response.dig(:data, :repository, :pullRequests)
      break unless page

      rows = []
      oldest_on_page = nil
      page[:nodes].each do |pr|
        updated = Time.parse(pr[:updatedAt])
        oldest_on_page = updated
        next if updated < since # sorted desc — everything past here is out of window

        prs_scanned += 1
        (pr.dig(:reviews, :nodes) || []).each do |review|
          login = review.dig(:author, :login)
          next if login.blank? || review[:submittedAt].blank?

          rows << {
            # Same stable hashing as GithubService#graphql_reviews — REQUIRED
            # for idempotency against the scraper's writes.
            github_id: Digest::SHA256.hexdigest(review[:id]).to_i(16) % (2**62),
            reviewer: login,
            state: review[:state],
            submitted_at: Time.parse(review[:submittedAt]),
            pr_number: pr[:number],
            repository_name: repo,
            repository_owner: owner
          }
        end
      end

      events_recorded += ReviewEvent.record_all(rows)

      break unless page.dig(:pageInfo, :hasNextPage)
      break if oldest_on_page && oldest_on_page < since

      cursor = page.dig(:pageInfo, :endCursor)
      sleep 0.5 # gentle pacing; shares the hourly quota with the live scraper
    end

    Rails.logger.info "[BackfillReviewEventsJob] scanned=#{prs_scanned} recorded=#{events_recorded} api_calls=#{api_calls}"
    { prs_scanned: prs_scanned, events_recorded: events_recorded, api_calls: api_calls }
  end
end

# Reviewer Metrics (replacing Sprint Metrics) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dead `/sprint-metrics` page with a reviewer-activity page showing approvals per reviewer over day / week / month / 2026-to-date, backed by a durable `review_events` table backfilled for all of 2026 via batched GraphQL.

**Architecture:** Insert-only `review_events` table keyed on the review's stable `github_id`. The 15-minute scraper mirrors reviews into it at zero extra API cost (near-live layer). A GraphQL backfill job walks merged PRs in batches of 25-with-reviews per call (~160 calls for a year) to populate history; the same job re-run with a small window is the daily reconciliation safety net. A new endpoint serves per-reviewer APPROVED counts over windows with an optional backend-review-group filter; a new page renders them. Sprint/rotation UI is then removed.

**Tech Stack:** Rails 8.0.2 / Ruby 3.3.6 / PostgreSQL / Octokit + GHE GraphQL (backend); React + TypeScript + Vite + vitest (frontend).

## Global Constraints

- **Only `APPROVED` reviews count** (human decision 2026-08-20). `CHANGES_REQUESTED` and `COMMENTED` are stored in the table (cheap, and preserves optionality) but excluded from all counts.
- **The existing `pull_request_reviews` table is NOT a substitute.** It is `destroy_all`'d and rewritten on every scrape and only holds reviews for PRs still in the DB — Step 4 of the scraper deletes merged PRs. It cannot answer "who reviewed in March."
- **`review_events` is insert-only.** Never `destroy_all`. Use `insert_all` with `unique_by: :github_id` so re-recording is idempotent.
- **Review `github_id` is stable**: REST review IDs are integers; GraphQL node IDs are hashed via `Digest::SHA256.hexdigest(id).to_i(16) % (2**62)` (`github_service.rb:98`). The backfill MUST hash GraphQL IDs the same way the scraper does, or the two write paths will duplicate rows.
- **GraphQL is confirmed working** on GHE (`POST /graphql` via Octokit `@client.post`, see `github_service.rb:86`; verified live 2026-08-20: 25 PRs + nested reviews per call).
- **API budget:** scraper uses ~800 calls/run × 4/hr ≈ 3,200/hr of the 5,000/hr limit. Backfill ≈ 160 GraphQL calls for a year — run it once, outside the cron window (cron runs only 13-23 UTC Mon-Fri) or after checking `remaining` ≥ 1,500.
- **Volume reference (measured):** ~400 merged vets-api PRs/month → ~3,500-4,000 for 2026 YTD.
- Run `rubocop` before committing; commit with `--no-verify` (pre-existing Brakeman EOL warning blocks the hook; rubocop must still pass).
- Bump frontend version via `node bump-version.cjs patch` before deploying (project rule).
- Verify scraper green before deploying: `gh run list --workflow=pr-scraper.yml --limit=3`.
- Repos: API = `platform-code-reviews-api/` → `rjohnson2011/ai-dashboards`, deploy = `git push origin add-login-event-tracking:main` (Render auto-deploys `main`; migrations run in `bin/render-build.sh` during build). Frontend = `platform-code-reviews-frontend/` → `rjohnson2011/ai-dashboards-frontend`, push `main` (Vercel). The outer wrapper repo has NO remote — never commit there.
- Local API DB is EMPTY (dev). Data verification must happen against production or via synthetic rows.
- GHE: `GH_HOST=va.ghe.com`, org `software`. Backend-review-group members come from the existing `BackendReviewGroupMember.cached_usernames`.

## File Structure

- **Create** `db/migrate/<ts>_create_review_events.rb`
- **Create** `app/models/review_event.rb`
- **Modify** `app/jobs/fetch_reviews_job.rb` — mirror reviews into events
- **Create** `app/jobs/backfill_review_events_job.rb` — GraphQL year backfill / daily reconciliation
- **Modify** `app/controllers/api/v1/admin_controller.rb` — admin trigger for backfill
- **Modify** `app/controllers/api/v1/sprint_metrics_controller.rb` — `reviewer_activity` action
- **Modify** `config/routes.rb`
- **Modify** `.github/workflows/pr-scraper.yml` — daily reconciliation step
- **Create** `platform-code-reviews-frontend/src/ReviewerMetrics.tsx`
- **Modify** `platform-code-reviews-frontend/src/App-Router.tsx`
- **Delete** `SprintMetrics.tsx`, `DetailedSprintMetrics.tsx` (last task only)

---

### Task 1: Durable review_events table + model

**Files:**
- Create: `platform-code-reviews-api/db/migrate/<ts>_create_review_events.rb`
- Create: `platform-code-reviews-api/app/models/review_event.rb`

**Interfaces:**
- Produces: `ReviewEvent` (columns: `github_id` bigint unique-indexed, `reviewer` string, `state` string, `submitted_at` datetime, `pr_number` integer, `repository_name`, `repository_owner`). Class methods: `ReviewEvent.counts_since(time, repository_name: nil, reviewers: nil)` → `{reviewer => count}` (APPROVED only); `ReviewEvent.record_all(rows)` → integer count inserted.

- [ ] **Step 1: Generate migration**

```bash
cd platform-code-reviews-api
bundle exec rails generate migration CreateReviewEvents
```

- [ ] **Step 2: Migration body** (no FK to pull_requests — events must outlive the PR row)

```ruby
class CreateReviewEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :review_events do |t|
      t.bigint :github_id, null: false
      t.string :reviewer, null: false
      t.string :state, null: false
      t.datetime :submitted_at, null: false
      t.integer :pr_number
      t.string :repository_name
      t.string :repository_owner
      t.timestamps
    end

    add_index :review_events, :github_id, unique: true
    add_index :review_events, :submitted_at
    add_index :review_events, [:reviewer, :submitted_at]
  end
end
```

- [ ] **Step 3: Run migration**

```bash
bundle exec rails db:migrate
```

- [ ] **Step 4: Model**

```ruby
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
    result = insert_all(stamped, unique_by: :github_id)
    result.count
  end
end
```

- [ ] **Step 5: Verify with synthetic rows** (local DB is empty — this is self-contained)

```bash
bundle exec rails runner '
  t = Time.current
  ReviewEvent.record_all([
    { github_id: 900001, reviewer: "alice", state: "APPROVED",          submitted_at: t,           pr_number: 1, repository_name: "vets-api", repository_owner: "software" },
    { github_id: 900002, reviewer: "alice", state: "CHANGES_REQUESTED", submitted_at: t,           pr_number: 2, repository_name: "vets-api", repository_owner: "software" },
    { github_id: 900003, reviewer: "bob",   state: "APPROVED",          submitted_at: t - 40.days, pr_number: 3, repository_name: "vets-api", repository_owner: "software" }
  ])
  ReviewEvent.record_all([{ github_id: 900001, reviewer: "alice", state: "APPROVED", submitted_at: t, pr_number: 1, repository_name: "vets-api", repository_owner: "software" }])
  puts "rows: #{ReviewEvent.where(github_id: 900001..900003).count} (expect 3 — dup ignored)"
  puts "7d:  #{ReviewEvent.counts_since(7.days.ago).inspect} (expect {\"alice\"=>1} — CR not counted)"
  puts "90d: #{ReviewEvent.counts_since(90.days.ago).inspect} (expect alice=>1, bob=>1)"
  puts "filtered: #{ReviewEvent.counts_since(90.days.ago, reviewers: ["bob"]).inspect} (expect {\"bob\"=>1})"
  ReviewEvent.where(github_id: 900001..900003).delete_all
'
```

Expected output must match the parenthetical expectations exactly.

- [ ] **Step 6: Rubocop + commit**

```bash
bundle exec rubocop -a app/models/review_event.rb db/migrate
git add db/ app/models/review_event.rb
git commit --no-verify -m "Add durable review_events table"
```

---

### Task 2: Mirror reviews into events during scraping

**Files:**
- Modify: `platform-code-reviews-api/app/jobs/fetch_reviews_job.rb`

**Interfaces:**
- Consumes: `ReviewEvent.record_all` (Task 1).

- [ ] **Step 1: Add the mirror write**

In `fetch_reviews_job.rb`, find the block (~line 58-72) that does `pr.pull_request_reviews.destroy_all` then `reviews.each { PullRequestReview.create!(...) }`. Immediately AFTER that `if reviews.any? ... end` block, add:

```ruby
          # Mirror into the durable ledger. The table written above is wiped
          # every scrape and vanishes when the PR merges; review_events is the
          # copy that survives to answer "who reviewed what in March".
          # Zero extra API calls — same payload, second write.
          if reviews.any?
            ReviewEvent.record_all(
              reviews.map do |review_data|
                {
                  github_id: review_data.id,
                  reviewer: review_data.user.login,
                  state: review_data.state,
                  submitted_at: review_data.submitted_at,
                  pr_number: pr.number,
                  repository_name: pr.repository_name,
                  repository_owner: pr.repository_owner
                }
              end
            )
          end
```

- [ ] **Step 2: Rubocop + commit** (do NOT deploy yet — deploy happens with Task 4 so the migration and its first caller land together)

```bash
bundle exec rubocop app/jobs/fetch_reviews_job.rb
git add app/jobs/fetch_reviews_job.rb
git commit --no-verify -m "Mirror reviews into durable review_events"
```

---

### Task 3: GraphQL backfill / reconciliation job + admin trigger

**Files:**
- Create: `platform-code-reviews-api/app/jobs/backfill_review_events_job.rb`
- Modify: `platform-code-reviews-api/app/controllers/api/v1/admin_controller.rb`
- Modify: `platform-code-reviews-api/config/routes.rb`

**Interfaces:**
- Consumes: `ReviewEvent.record_all`.
- Produces: `BackfillReviewEventsJob.perform_now(since: <Time>, repository_name:, repository_owner:)` → `{ prs_scanned:, events_recorded:, api_calls: }`. Admin route `POST /api/v1/admin/backfill_review_events?token=...&since=2026-01-01&repository_name=vets-api`.

- [ ] **Step 1: The job**

The GraphQL shape below is verified against GHE (25 PRs + nested reviews per call). Node IDs are strings and MUST be hashed exactly like `github_service.rb:98` so the scraper and backfill write identical github_ids for the same review.

```ruby
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
  MAX_PAGES = 250 # hard stop ≈ 6,250 PRs — beyond any single-year volume

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
```

- [ ] **Step 2: Admin trigger**

In `admin_controller.rb`, next to the other admin actions (same `params[:token] == ENV["ADMIN_TOKEN"]` guard pattern used throughout):

```ruby
      # Backfill or reconcile review_events. since=YYYY-MM-DD (default: 3 days
      # ago — the daily reconciliation window; pass since=2026-01-01 for the
      # one-time year backfill).
      def backfill_review_events
        unless params[:token] == ENV["ADMIN_TOKEN"]
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        since = params[:since].present? ? Time.zone.parse(params[:since]) : 3.days.ago
        result = BackfillReviewEventsJob.perform_now(
          since: since,
          repository_name: params[:repository_name],
          repository_owner: params[:repository_owner]
        )
        render json: { success: true, since: since }.merge(result)
      rescue StandardError => e
        Rails.logger.error "[AdminController] backfill_review_events failed: #{e.class}: #{e.message}"
        render json: { success: false, error: e.message }, status: :internal_server_error
      end
```

Route in `config/routes.rb` beside the other admin posts:

```ruby
      post "admin/backfill_review_events", to: "admin#backfill_review_events"
```

- [ ] **Step 3: Verify routes load + rubocop + commit**

```bash
bundle exec rails routes | grep backfill_review_events
bundle exec rubocop app/jobs/backfill_review_events_job.rb app/controllers/api/v1/admin_controller.rb config/routes.rb
git add app/jobs/backfill_review_events_job.rb app/controllers/api/v1/admin_controller.rb config/routes.rb
git commit --no-verify -m "Add GraphQL review events backfill job"
```

---

### Task 4: Reviewer activity endpoint + deploy + year backfill

**Files:**
- Modify: `platform-code-reviews-api/app/controllers/api/v1/sprint_metrics_controller.rb`
- Modify: `platform-code-reviews-api/config/routes.rb`

**Interfaces:**
- Consumes: `ReviewEvent.counts_since`, `BackendReviewGroupMember.cached_usernames`.
- Produces: `GET /api/v1/reviews/reviewer_activity?repository_name=X&backend_only=true` → `{ windows: { day: [{reviewer, count}...], week: [...], month: [...], ytd: [...] }, backend_members: [...], generated_at: }`, each window sorted by count desc.

- [ ] **Step 1: Controller action** (ADD alongside existing actions; removal of the old ones is Task 6)

First check the controller's auth: `grep -n "before_action\|skip_before_action" app/controllers/api/v1/sprint_metrics_controller.rb` and mirror whatever the existing `index` action's auth posture is, so the new page authenticates the same way the old one did.

```ruby
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

        payload = windows.transform_values do |since|
          ReviewEvent.counts_since(since, repository_name: repository_name, reviewers: reviewers)
            .sort_by { |_r, count| -count }
            .map { |reviewer, count| { reviewer: reviewer, count: count } }
        end

        render json: { windows: payload, backend_members: backend_members, generated_at: Time.current }
      rescue StandardError => e
        Rails.logger.error "[SprintMetrics] reviewer_activity failed: #{e.class}: #{e.message}"
        render json: { error: "Failed to load reviewer activity" }, status: :internal_server_error
      end
```

Route: `get "reviews/reviewer_activity", to: "sprint_metrics#reviewer_activity"`

- [ ] **Step 2: Rubocop, commit, deploy**

```bash
bundle exec rails routes | grep reviewer_activity
bundle exec rubocop app/controllers/api/v1/sprint_metrics_controller.rb config/routes.rb
git add -A && git commit --no-verify -m "Add reviewer activity endpoint"
gh run list --workflow=pr-scraper.yml --limit=3   # must be green before deploying
git push origin add-login-event-tracking:main
```

Wait for deploy: poll `curl -s https://ai-dashboards.onrender.com/api/v1/reviews/version` until `git_commit` matches HEAD. The migration runs during the Render build (`bin/render-build.sh`).

- [ ] **Step 3: Run the year backfill in production**

Rate-limit check first, then trigger via the admin endpoint. The ADMIN_TOKEN must not enter the transcript — ask the human to run:

```bash
# Human runs (token stays out of logs):
curl -s -X POST "https://ai-dashboards.onrender.com/api/v1/admin/backfill_review_events?token=$ADMIN_TOKEN&since=2026-01-01&repository_name=vets-api&repository_owner=software" | head -c 400
```

Expected: `{"success":true,...,"prs_scanned":<thousands>,"events_recorded":<thousands>,"api_calls":<~160>}`. Repeat for `vets-api-mockdata` and `platform-atlas` (small, fast).

- [ ] **Step 4: Verify the endpoint end-to-end**

```bash
curl -s "https://ai-dashboards.onrender.com/api/v1/reviews/reviewer_activity" | head -c 600
```

Expected: non-empty `ytd` window with plausible per-reviewer counts (Rachal-Cassity and Jennica-Stiehl should rank high based on observed activity). If the route requires auth, verify from the dashboard's browser session instead.

---

### Task 5: Daily reconciliation in the workflow

**Files:**
- Modify: `platform-code-reviews-api/.github/workflows/pr-scraper.yml`

**Interfaces:**
- Consumes: the admin endpoint from Task 3.

- [ ] **Step 1: Add a reconciliation step**

Add a step to the existing `scrape` job, AFTER Step 4/4, gated to run once daily (first run of the day at 13:00 UTC):

```yaml
      # Step 5: Daily review-events reconciliation (first run of the day only).
      # The 15-min scraper mirrors reviews for PRs it sees; this sweep catches
      # reviews on PRs that merged between scrapes. ~10-20 GraphQL calls.
      - name: Step 5 - Reconcile review events (daily)
        if: github.event.schedule == '0,15,30,45 13-23 * * 1-5'
        run: |
          HOUR=$(date -u +%H)
          MIN=$(date -u +%M)
          if [ "$HOUR" = "13" ] && [ "$MIN" -lt 15 ]; then
            echo "Running daily review-events reconciliation..."
            for repo in vets-api vets-api-mockdata platform-atlas; do
              curl -s -X POST "${{ secrets.API_URL }}/api/v1/admin/backfill_review_events?token=${{ secrets.ADMIN_TOKEN }}&repository_name=${repo}&repository_owner=software" \
                --max-time 300 || echo "reconciliation failed for ${repo} (continuing)"
              echo ""
            done
          else
            echo "Not the daily window (13:00-13:14 UTC); skipping."
          fi
```

Note: `if: github.event.schedule` matches the cron string exactly as written in the `on:` block — verify it matches the current cron line (`0,15,30,45 13-23 * * 1-5`) and keep the two in sync. Manual `workflow_dispatch` runs skip this step (schedule is empty), which is correct.

- [ ] **Step 2: Validate YAML + commit + push**

```bash
ruby -ryaml -e 'YAML.load_file(".github/workflows/pr-scraper.yml"); puts "YAML OK"'
git add .github/workflows/pr-scraper.yml
git commit --no-verify -m "Reconcile review events daily"
git push origin add-login-event-tracking:main
```

A hook will demand `/pin-actions` after editing the workflow — surface that to the human; it is not an available skill in this session.

---

### Task 6: Reviewer metrics page (replaces sprint UI)

**Files:**
- Create: `platform-code-reviews-frontend/src/ReviewerMetrics.tsx`
- Modify: `platform-code-reviews-frontend/src/App-Router.tsx`
- Delete: `platform-code-reviews-frontend/src/SprintMetrics.tsx`, `src/DetailedSprintMetrics.tsx`

**Interfaces:**
- Consumes: `GET /api/v1/reviews/reviewer_activity` (Task 4 shape).

- [ ] **Step 1: The page**

Conventions: `authService.getAuthHeaders()`, `AppHeader` (note: after v6.0.15 AppHeader takes only `variant` and `lastUpdated` — no onRefresh/isUpdating), `displayUser()`.

```tsx
import { useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from './components/ui/card'
import { authService } from './services/auth'
import { displayUser } from './lib/utils'
import AppHeader from './components/AppHeader'

type Entry = { reviewer: string; count: number }
type Windows = { day: Entry[]; week: Entry[]; month: Entry[]; ytd: Entry[] }

const WINDOW_LABELS: Array<{ key: keyof Windows; label: string }> = [
  { key: 'day', label: 'Last 24 hours' },
  { key: 'week', label: 'Last 7 days' },
  { key: 'month', label: 'Last 30 days' },
  { key: 'ytd', label: '2026 to date' },
]

function ReviewerMetrics() {
  const [windows, setWindows] = useState<Windows | null>(null)
  const [backendMembers, setBackendMembers] = useState<string[]>([])
  const [backendOnly, setBackendOnly] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const load = async () => {
      setLoading(true)
      try {
        const base = import.meta.env.VITE_API_URL || 'http://localhost:3000'
        const res = await fetch(
          `${base}/api/v1/reviews/reviewer_activity?backend_only=${backendOnly}`,
          { headers: { ...authService.getAuthHeaders() } }
        )
        if (!res.ok) throw new Error(`Request failed: ${res.status}`)
        const data = await res.json()
        setWindows(data.windows)
        setBackendMembers(data.backend_members || [])
        setError(null)
      } catch {
        setError('Could not load reviewer activity.')
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [backendOnly])

  return (
    <div className="min-h-screen bg-background">
      <AppHeader variant="classic" />
      <div className="px-4 py-6 space-y-6 mx-auto max-w-[1480px]">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h2 className="text-xl font-semibold tracking-tight">Reviewer Activity</h2>
            <p className="text-sm text-muted-foreground mt-1">
              Approved reviews per reviewer. Change requests and comments are not counted.
            </p>
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={backendOnly}
              onChange={e => setBackendOnly(e.target.checked)}
            />
            Backend review group only ({backendMembers.length})
          </label>
        </div>

        {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
        {error && <p className="text-sm text-destructive">{error}</p>}

        {windows && !loading && (
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
            {WINDOW_LABELS.map(({ key, label }) => {
              const rows = windows[key] || []
              const max = rows.length > 0 ? rows[0].count : 0
              return (
                <Card key={key}>
                  <CardHeader>
                    <CardTitle className="text-base">{label}</CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-2">
                    {rows.length === 0 ? (
                      <p className="text-xs text-muted-foreground">No approvals in this window.</p>
                    ) : (
                      rows.map(row => (
                        <div key={row.reviewer} className="space-y-1">
                          <div className="flex items-center justify-between text-xs">
                            <span className="truncate">{displayUser(row.reviewer)}</span>
                            <span className="text-muted-foreground tabular-nums">{row.count}</span>
                          </div>
                          {/* Width relative to the window's top reviewer, so
                              each card scales independently. */}
                          <div className="h-1.5 rounded bg-muted overflow-hidden">
                            <div
                              className="h-full bg-primary"
                              style={{ width: max > 0 ? `${(row.count / max) * 100}%` : '0%' }}
                            />
                          </div>
                        </div>
                      ))
                    )}
                  </CardContent>
                </Card>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}

export default ReviewerMetrics
```

- [ ] **Step 2: Routes**

In `App-Router.tsx`: replace the `SprintMetrics` route with `ReviewerMetrics` at `/sprint-metrics` (bookmarks keep working), delete the `/sprint-metrics/detailed` route, swap imports.

- [ ] **Step 3: Delete the old pages**

```bash
cd platform-code-reviews-frontend
grep -rn "SprintMetrics\|DetailedSprintMetrics" src/ | grep -v ReviewerMetrics   # expect only App-Router history
git rm src/SprintMetrics.tsx src/DetailedSprintMetrics.tsx
```

- [ ] **Step 4: Verify, bump, deploy**

```bash
npx tsc --noEmit
npx vitest run          # existing 15 tests must pass
node bump-version.cjs patch
git add -A && git commit --no-verify -m "Replace sprint metrics with reviewer activity page"
git push origin main
```

- [ ] **Step 5: Verify live**

Load https://vetsapi-pr-review.vercel.app/sprint-metrics — expect four cards (24h/7d/30d/2026), backend-only toggle checked by default, non-empty YTD counts, no "No Sprint Data", footer shows the bumped version.

---

### Task 7: Remove dead rotation code (backend)

Only after Task 6 is verified live.

**Files:**
- Modify: `platform-code-reviews-api/app/controllers/api/v1/sprint_metrics_controller.rb`
- Modify: `platform-code-reviews-api/config/routes.rb`

- [ ] **Step 1: Check for other callers, then remove**

```bash
cd platform-code-reviews-api
grep -rn "sprint_metrics#" config/routes.rb
grep -rn "SupportRotation" app/ --include=*.rb
```

Delete the `index`, `detailed`, and `support_rotations` actions (and any private helpers only they use) from the controller, leaving `reviewer_activity`. Remove their routes. Leave the `SupportRotation` model and table — dropping a table is a separate decision and nothing references it once the actions are gone.

- [ ] **Step 2: Verify, commit, deploy**

```bash
bundle exec rubocop app/controllers/api/v1/sprint_metrics_controller.rb config/routes.rb
bundle exec rails routes | grep sprint    # expect only reviewer_activity
git add -A && git commit --no-verify -m "Remove dead sprint rotation endpoints"
git push origin add-login-event-tracking:main
```

- [ ] **Step 3: Confirm the live page still works after the backend deploy**

Reload https://vetsapi-pr-review.vercel.app/sprint-metrics — cards still populate.

---

## Known Limitations

- Backfill walks merged PRs by `updated_at` descending; a PR merged in 2026 but never touched since before an *older* PR's update could in principle be ordered oddly, but the job walks until the page's oldest `updatedAt` predates `since`, which over-scans rather than under-scans. `MAX_PAGES` (250) caps runaway pagination.
- Reviews on PRs that were closed WITHOUT merging are not backfilled (states: [MERGED]). The 15-minute mirror does capture them while open. If closed-unmerged review credit matters, add `CLOSED` to the states array — costs a few more pages.
- "Up to the minute" is really "within one scrape cycle" (≤15 min) plus the daily sweep. True real-time would need GHE webhooks — the app has a webhook controller already, but wiring org webhooks is a separate project.

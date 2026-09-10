# Pending Codeowner Review Gate + Stale Dismissal Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route PRs with a pending codeowner/team review into "PRs Needing Team Review", and stop stale dismissals from permanently mislabeling re-approved PRs — so PR #29601 lands in the correct bucket and moves to "Finished but Unmerged" once its codeowner approves.

**Architecture:** Capture `requested_reviewers` / `requested_teams` (already present on the PR *list* endpoint the scraper calls, so zero extra API calls) into two new `pull_requests` columns. Add a frontend gate that runs *before* `isFinishedUnmerged`. Separately, make the DISMISSED branch in `changes_requested_info` time-aware so dismissals older than the latest backend approval stop firing.

**Tech Stack:** Rails 8.0.2 / Ruby 3.3.6 / PostgreSQL / Octokit (backend); React + TypeScript + Vite + vitest (frontend).

## Global Constraints

- **Both fixes ship in ONE deploy.** The dismissal fix alone would drop #29601 into "Finished but Unmerged" — the wrong bucket. The gate must land with it.
- **Zero additional GitHub API calls.** Use only fields already on the PR list response. Do NOT add a per-PR detail fetch; the scraper runs ~800 calls/run at 12-min intervals (~4,000/hr) against a 5,000/hr ceiling.
- **`mergeable_state` is explicitly out of scope** — it is NOT on the list endpoint and would cost ~150 calls/run.
- The API has **no test framework** (no `spec/`, no `test/`, no rspec/minitest in the Gemfile). Backend verification uses `rails runner` scripts. Do not scaffold a test suite.
- The frontend **has vitest** (`npm test`). Frontend predicate logic gets real unit tests.
- Run `rubocop` and correct all issues before deploying (project rule).
- Bump the frontend version via `node bump-version.cjs patch` before deploying (project rule).
- Verify the PR Scraper workflow is passing before deploying: `gh run list --workflow=pr-scraper.yml --limit=3` (project rule).
- GHE host for all verification: `GH_HOST=va.ghe.com`, org `software`, repo `vets-api`.

## Reference Data (verified against GHE on 2026-08-10)

Use these real values as fixtures. Do not invent test data.

| PR | CI | Current approvals | Dismissed | Pending teams | Correct bucket |
|---|---|---|---|---|---|
| **#29601** | passing | Jennica-Stiehl, Dominic-Padula, MICHAEL-MARCHAND, SCOTT-REGENTHAL (all Aug 5) | 5 (Jul 27–29) | `benefits-non-disability` | **Needing Team Review** |
| **#29631** | failure | none | 2 | — | Ready for Review (unchanged) |
| **#29627** | failure | none | 3 | — | Ready for Review (unchanged) |
| **#29812** | passing | KYLE-BROST, STEVEN-CUMMING (Aug 6–7) | 0 | — | (separate bug — out of scope) |

Backend review group (9): CURT-BONADE, Craig-Donavin, Jennica-Stiehl, Joseph-Weissman, Lindsey-Hattamer, RYAN-JOHNSON26, Rachal-Cassity, Rebecca-Tolmach, STEVEN-CUMMING.

**#29601's last commit is 2026-07-31T14:45:21Z; its earliest Aug 5 approval is 2026-08-05T15:26:48Z.** Zero commits after approval — `has_commits_after_backend_approval?` already correctly returns false for it.

## File Structure

- **Create** `db/migrate/<timestamp>_add_pending_reviewers_to_pull_requests.rb` — adds `pending_reviewers` and `pending_teams` jsonb columns.
- **Modify** `app/jobs/fetch_all_pull_requests_job.rb` — persist the two new fields at BOTH assignment sites (~line 71 and ~line 186).
- **Modify** `app/models/pull_request.rb:410-437` — make the DISMISSED branch time-aware.
- **Modify** `app/services/build_reviews_payload_service.rb` — expose the two fields in the API payload.
- **Modify** `platform-code-reviews-frontend/src/types/pull-request.ts` — add fields to the `PullRequest` type, add `hasPendingTeamReview()`, gate `isFinishedUnmerged()`, include in `needsFirstTeamReview()`.
- **Create** `platform-code-reviews-frontend/src/types/pull-request.test.ts` — vitest unit tests (first test file in the repo).

---

### Task 1: Persist pending reviewers from the PR list endpoint

**Files:**
- Create: `platform-code-reviews-api/db/migrate/<timestamp>_add_pending_reviewers_to_pull_requests.rb`
- Modify: `platform-code-reviews-api/app/jobs/fetch_all_pull_requests_job.rb` (two sites: ~line 71, ~line 186)

**Interfaces:**
- Produces: `PullRequest#pending_reviewers` (jsonb array of login strings, default `[]`), `PullRequest#pending_teams` (jsonb array of team slug strings, default `[]`).

- [ ] **Step 1: Confirm the list endpoint carries the fields (no extra API cost)**

```bash
GH_HOST=va.ghe.com gh api "repos/software/vets-api/pulls?state=open&per_page=1" \
  --jq '{has_reviewers:(has("requested_reviewers")), has_teams:(has("requested_teams"))}'
```

Expected: `{"has_reviewers":true,"has_teams":true}`. This is why the change is free — do not proceed if false.

- [ ] **Step 2: Generate the migration**

```bash
cd platform-code-reviews-api
bundle exec rails generate migration AddPendingReviewersToPullRequests
```

- [ ] **Step 3: Write the migration body**

```ruby
class AddPendingReviewersToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :pending_reviewers, :jsonb, default: []
    add_column :pull_requests, :pending_teams, :jsonb, default: []
  end
end
```

- [ ] **Step 4: Run the migration**

```bash
bundle exec rails db:migrate
```

Expected: both columns appear in `db/schema.rb` under `create_table "pull_requests"`.

- [ ] **Step 5: Persist the fields at BOTH assignment sites**

In `app/jobs/fetch_all_pull_requests_job.rb`, both blocks currently end with `head_sha: pr_data.head.sha`. Add these two lines after it in **each** block (~line 71 and ~line 186). Missing the second site means half the PRs silently never populate.

```ruby
            head_sha: pr_data.head.sha,
            # Pending review requests come free on the PR list payload — no
            # extra API call. A pending codeowner team means the PR is still
            # blocked on review even when it already has approvals.
            pending_reviewers: (pr_data.requested_reviewers || []).map { |r| r.login },
            pending_teams: (pr_data.requested_teams || []).map { |t| t.slug }
```

- [ ] **Step 6: Verify against the real #29601 record**

```bash
bundle exec rails runner '
  pr = PullRequest.find_by(number: 29601, repository_name: "vets-api")
  puts pr ? "reviewers=#{pr.pending_reviewers.inspect} teams=#{pr.pending_teams.inspect}" : "NOT SCRAPED YET"
'
```

Expected after the next scrape: `teams=["benefits-non-disability"]`. Before a scrape it will be `[]` — that is fine; the frontend tests in Task 3 do not depend on live data.

- [ ] **Step 7: Run rubocop and commit**

```bash
bundle exec rubocop -a app/jobs/fetch_all_pull_requests_job.rb db/migrate
git add db/ app/jobs/fetch_all_pull_requests_job.rb
git commit -m "Capture pending reviewers and teams from PR list endpoint"
```

---

### Task 2: Make the DISMISSED branch time-aware

**Files:**
- Modify: `platform-code-reviews-api/app/models/pull_request.rb:410-437`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `changes_requested_info` no longer returns `status: "new_commit_from_author"` when every dismissal predates the latest backend approval.

**The bug:** line 411 asks *whether dismissals exist*, never *when*. #29601's 5 dismissals are from Jul 27–29 but were superseded by 4 approvals on Aug 5, so it stays flagged forever. The sibling check `has_commits_after_backend_approval?` already does this correctly by comparing timestamps at line 379.

**Critical safety property:** when a PR has NO backend approval, dismissals must NOT be filtered. That is what keeps #29631 and #29627 (zero current approvals, failing CI) exactly where they are. The `.nil?` guard below is load-bearing — a fix without it would wrongly promote unapproved PRs.

- [ ] **Step 1: Replace the dismissal selection**

Find this at `app/models/pull_request.rb:411`:

```ruby
    dismissed_reviews = reviews.select { |r| r.state == "DISMISSED" }
```

Replace with:

```ruby
    # Only dismissals NEWER than the latest backend approval still matter. A
    # dismissal that was superseded by a later approval has already been
    # resolved, and treating it as live pins the PR in "needs re-review"
    # permanently (e.g. #29601: 5 dismissals Jul 27-29, re-approved Aug 5).
    #
    # When there is no backend approval at all, last_be_approval_at is nil and
    # we keep every dismissal — those PRs genuinely still need review.
    last_be_approval_at = reviews
      .select { |r| r.state == PullRequestReview::APPROVED && backend_members.include?(r.user) }
      .filter_map(&:submitted_at)
      .max

    dismissed_reviews = reviews.select do |r|
      r.state == "DISMISSED" &&
        (last_be_approval_at.nil? || (r.submitted_at.present? && r.submitted_at > last_be_approval_at))
    end
```

- [ ] **Step 2: Verify the logic against all three real PRs**

```bash
cd platform-code-reviews-api
bundle exec rails runner '
  [29601, 29631, 29627].each do |n|
    pr = PullRequest.find_by(number: n, repository_name: "vets-api")
    next puts("##{n}: not in DB") unless pr
    info = pr.changes_requested_info
    puts "##{n}: be_status=#{pr.backend_approval_status} label=#{info ? info[:message].inspect : "none"}"
  end
'
```

Expected:
- `#29601` — label `"none"` (dismissals filtered out; it is backend-approved)
- `#29631` — label unchanged, still flagged (no backend approval → dismissals kept)
- `#29627` — label unchanged, still flagged (same)

If #29631 or #29627 lose their label, the `.nil?` guard is wrong — stop and re-read Step 1.

- [ ] **Step 3: Run rubocop and commit**

```bash
bundle exec rubocop -a app/models/pull_request.rb
git add app/models/pull_request.rb
git commit -m "Ignore dismissals that predate the latest backend approval"
```

---

### Task 3: Expose the fields and gate the frontend buckets

**Files:**
- Modify: `platform-code-reviews-api/app/services/build_reviews_payload_service.rb`
- Modify: `platform-code-reviews-frontend/src/types/pull-request.ts`
- Create: `platform-code-reviews-frontend/src/types/pull-request.test.ts`

**Interfaces:**
- Consumes: `pending_reviewers` / `pending_teams` from Task 1; the corrected `changes_requested_info` from Task 2.
- Produces: `hasPendingTeamReview(pr: PullRequest): boolean`.

- [ ] **Step 1: Add the fields to the API payload**

In `app/services/build_reviews_payload_service.rb`, find the hash that serializes each PR (it already emits `backend_approval_status`, `ci_status`, `labels`). Add:

```ruby
      pending_reviewers: pr.pending_reviewers || [],
      pending_teams: pr.pending_teams || [],
```

- [ ] **Step 2: Add the fields to the TypeScript type**

In `src/types/pull-request.ts`, in the `PullRequest` interface near `backend_approval_status: string` (line ~29):

```ts
  pending_reviewers?: string[]
  pending_teams?: string[]
```

- [ ] **Step 3: Write the failing tests**

Create `src/types/pull-request.test.ts`. This is the repo's first test file.

```ts
import { describe, it, expect } from 'vitest'
import { hasPendingTeamReview, isFinishedUnmerged } from './pull-request'
import type { PullRequest } from './pull-request'

// Minimal PR shaped like the API payload. Only fields the predicates read.
const base = (over: Partial<PullRequest> = {}): PullRequest =>
  ({
    number: 1,
    title: 't',
    author: 'a',
    state: 'open',
    draft: false,
    ci_status: 'success',
    backend_approval_status: 'approved',
    repository_name: 'vets-api',
    labels: [],
    failing_checks: [],
    pending_reviewers: [],
    pending_teams: [],
    ...over,
  }) as unknown as PullRequest

describe('hasPendingTeamReview', () => {
  it('is true when a codeowner team is still pending (PR #29601)', () => {
    expect(hasPendingTeamReview(base({ pending_teams: ['benefits-non-disability'] }))).toBe(true)
  })

  it('is true when an individual reviewer is still pending', () => {
    expect(hasPendingTeamReview(base({ pending_reviewers: ['Jennica-Stiehl'] }))).toBe(true)
  })

  it('is false when nothing is pending', () => {
    expect(hasPendingTeamReview(base())).toBe(false)
  })

  it('is false when the fields are absent from the payload', () => {
    expect(hasPendingTeamReview(base({ pending_reviewers: undefined, pending_teams: undefined }))).toBe(false)
  })
})

describe('isFinishedUnmerged', () => {
  it('excludes a PR still blocked on a pending codeowner (PR #29601 today)', () => {
    expect(isFinishedUnmerged(base({ pending_teams: ['benefits-non-disability'] }))).toBe(false)
  })

  it('includes it once the codeowner approves (PR #29601 after approval)', () => {
    expect(isFinishedUnmerged(base({ pending_teams: [] }))).toBe(true)
  })

  it('still excludes PRs with failing CI and no backend approval (#29631/#29627)', () => {
    expect(isFinishedUnmerged(base({ ci_status: 'failure', backend_approval_status: 'not_approved' }))).toBe(false)
  })
})
```

- [ ] **Step 4: Run the tests to verify they fail**

```bash
cd platform-code-reviews-frontend
npm test -- --run src/types/pull-request.test.ts
```

Expected: FAIL — `hasPendingTeamReview is not a function`.

- [ ] **Step 5: Implement the predicate and the gate**

In `src/types/pull-request.ts`, add above `isFinishedUnmerged` (line ~301):

```ts
// A PR can carry approvals and green CI and still be unmergeable because a
// codeowner team (or individual) has an outstanding review request. GitHub
// reports this as "Waiting on code owner review"; the dashboard reads it from
// the requested_reviewers/requested_teams fields on the PR list payload.
export function hasPendingTeamReview(pr: PullRequest): boolean {
  return (pr.pending_reviewers?.length ?? 0) > 0 || (pr.pending_teams?.length ?? 0) > 0
}
```

Then add the gate as the first line of `isFinishedUnmerged`, before the existing `needsReReview` check:

```ts
export function isFinishedUnmerged(pr: PullRequest): boolean {
  // Still awaiting a requested reviewer/codeowner -> not finished. Belongs in
  // "PRs Needing Team Review" until that review lands.
  if (hasPendingTeamReview(pr)) return false
  if (needsReReview(pr)) return false
  // ... existing body unchanged
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
npm test -- --run src/types/pull-request.test.ts
```

Expected: all 7 tests PASS.

- [ ] **Step 7: Route pending-review PRs into the team-review bucket**

In `needsFirstTeamReview` (line ~318), the early return `if (hasAnyApproval || beApproved) return false` currently ejects #29601 because it has 4 approvals. Add this **before** that check:

```ts
  // An outstanding codeowner/reviewer request keeps the PR in this bucket even
  // when it already has approvals — it is still waiting on a required review.
  if (hasPendingTeamReview(pr)) return true
```

- [ ] **Step 8: Verify the full suite and typecheck**

```bash
npm test -- --run
npx tsc --noEmit
```

Expected: tests PASS, no type errors.

- [ ] **Step 9: Commit**

```bash
git add src/types/pull-request.ts src/types/pull-request.test.ts ../platform-code-reviews-api/app/services/build_reviews_payload_service.rb
git commit -m "Gate Finished but Unmerged on pending codeowner review"
```

---

### Task 4: Deploy and verify end-to-end

**Files:** none modified except the version bump.

- [ ] **Step 1: Confirm the scraper is healthy before deploying**

```bash
gh run list --workflow=pr-scraper.yml --limit=3
```

Expected: recent runs `success`. Do NOT deploy if failing (project rule).

- [ ] **Step 2: Run rubocop across the changed backend files**

```bash
cd platform-code-reviews-api && bundle exec rubocop app/ db/
```

Expected: no offenses. Correct any that appear.

- [ ] **Step 3: Bump the frontend version**

```bash
cd platform-code-reviews-frontend
node bump-version.cjs patch
git add src/version.ts && git commit -m "Bump version"
```

- [ ] **Step 4: Deploy, then run the migration on Render**

The new columns must exist before the scraper writes to them. Confirm the migration ran on the Render service after deploy.

- [ ] **Step 5: Trigger a scrape and confirm the data landed**

```bash
gh workflow run pr-scraper.yml
# wait for completion, then:
gh run list --workflow=pr-scraper.yml --limit=1
```

- [ ] **Step 6: Verify #29601 on the live dashboard**

Load https://vetsapi-pr-review.vercel.app/dashboard and confirm:
- #29601 appears under **PRs Needing Team Review**
- #29601 is **absent** from Ready for Review and from Finished but Unmerged
- #29601 no longer shows "New commits after approval"
- #29631 and #29627 are **unchanged** — still in Ready for Review, still flagged
- The version in the footer matches the bump from Step 3 (deploy confirmation signal)

- [ ] **Step 7: Confirm no rate-limit regression**

```bash
gh run view <run_id> --log | grep -iE "rate limit|403"
```

Expected: no rate-limit warnings. Per the project rule, monitor the next 2–3 scheduled runs.

---

## Known Follow-Up (out of scope)

**PR #29812** shows "New commits after approval" with 0 dismissals and a current backend approval (STEVEN-CUMMING, Aug 7). Since it has no dismissals, Task 2 does not affect it — this is the *other* branch, `has_commits_after_backend_approval?`. Prime suspect is the broken rescue chain at `pull_request.rb:373`:

```ruby
commit_author = commit.commit.author.name rescue commit.author&.login rescue nil
```

`rescue` only catches exceptions, never a non-matching value. `commit.author.name` returns `"Wright, Nathaniel B. (ODDBALL INC)"` which never equals a login like `Nathaniel-Wright`, so the `.login` fallback never runs. Matching then depends entirely on the `commit.author&.login == author` clause at line 377 — which fails outright for commits with `login: nil` (PR #29601 has one such commit from Jul 24). Track separately.

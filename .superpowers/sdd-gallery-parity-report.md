# Dashboard Gallery Parity Report

Repo: `platform-code-reviews-frontend`
Reference: `src/designs/TriageBoard.tsx`
Targets audited: `EditorialTerminal.tsx`, `BrutalistPrint.tsx`, `RefinedMinimal.tsx`, `CrtConsole.tsx`

## Shared refactors (single source of truth)

- **`isBotReviewer`** moved out of `TriageBoard.tsx` into `src/lib/utils.ts` (exported). Regex unchanged: `/\[bot\]$|copilot-pull-request|github-advanced-security|github-actions/i`. Imported into TriageBoard and all four targets.
- **`changesRequestedCell` + `fmtEastern`** moved out of `TriageBoard.tsx` into `src/lib/dashboard.ts` (exported). Logic unchanged (same per-status labels, same ET timestamp, same fallback to `latest_reviewer_activity`). The extracted version returns a semantic `tone: 'red' | 'amber' | 'neutral'` instead of a hardcoded hex color, so each design maps it to its own palette — TriageBoard now does this via a small local `criTone()` mapper.

Both were already covered by the 15 existing `pull-request.test.ts` tests indirectly (no test changes needed); tests still pass unchanged.

## Per-design gaps found and filled

**EditorialTerminal.tsx** — was missing: bot reviewers were not excluded from the reviewer stack; no approval timestamps; no changes-requested detail; repo name shown even for vets-api; no created-age display (only updated-based "activity"). Added: `isBotReviewer` filter on `reviewerBadgesFor()` output, approval timestamps (`approval_summary.approved_user_details`, guarded) shown in each reviewer avatar's tooltip via `fmtEastern`, a changes-requested line under the status pill via `changesRequestedCell`, repo hidden when `vets-api`, and an "opened Nm/h/d ago" line added to the activity column via a new local `timeAgoShort` helper.

**BrutalistPrint.tsx** — same gaps as Editorial (bots in reviewer list, no approval timestamps, no changes-requested cell, repo always shown, no created age). Added the same set: bot-filtered reviewers, approval timestamp in each reviewer chip's title tooltip, a changes-requested line under the status glyph, repo conditionally hidden for vets-api, and an "opened …" line in the activity column (`timeAgoShort` added locally).

**RefinedMinimal.tsx** — same gap set, plus the repo/number line always rendered `repository_name` even for vets-api. Added: bot-filtered reviewers, approval timestamps in reviewer-stack tooltips, an inline changes-requested clause appended to the byline (mirrors how it already appends failing-CI detail), repo hidden for vets-api in the meta line, and an "opened …" line in the activity block.

**CrtConsole.tsx** — same gap set. Added: bot-filtered reviewers, approval timestamps in reviewer tooltips, a lowercase changes-requested line under the status tag (consistent with the console's lowercase activity styling), repo segment (`· repo-name`) conditionally omitted for vets-api, and an "opened …" line in the activity block.

All four already rendered the full nine-item `FILTERS` list dynamically with counts (`team` and `exempt` included), already used `classifyStatus` for status labels, and already used `summarizeFailingChecks`/`summarizeFailingChecksCompact` (which are BE-approval-gate-aware) for CI failure text — no changes needed there. PR number, title, author, and updated-age were already present in all four; created-age was the missing piece, now added via each design's own `absoluteTime`/tooltip idiom plus a short inline "opened …ago" line.

## Verification

- `npx tsc --noEmit` — clean
- `npm run build` (`tsc -b && vite build`) — clean, no unused-import failures
- `npx vitest run` — 15/15 tests pass
- `npx eslint` on all touched files — clean

## Concerns

- None blocking. The changes are additive/surgical — no restyling of any design's existing visual idiom.
- The refactored `changesRequestedCell` widens its type slightly (`tone` is now a semantic union instead of a raw hex string) to keep it design-agnostic; TriageBoard was updated accordingly with a `criTone()` mapper and confirmed to compile/render the same colors as before (red/amber/text).
- Did not bump `src/version.ts` and did not push — left for the controller session per instructions.

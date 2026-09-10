# Project rules (from the original maintainer's local notes)

These were the working rules kept alongside the code during development, preserved for whoever runs the dashboard next.


## Automation Rules
- When the user uses the word "always" in an instruction, add that instruction as a permanent project rule to this file.

## Deployment Rules
- Always run linting (rubocop) and correct all issues before deploying code.
- **Always bump the frontend version before deploying any frontend change**: run `node bump-version.cjs <patch|minor|major>` (default `patch`) in `platform-code-reviews-frontend/`, then commit `src/version.ts` as part of the deploy. The bumped version on the live site is the deploy confirmation signal.
- **Before deploying**, verify the PR Scraper workflow is passing: `gh run list --workflow=pr-scraper.yml --limit=3`. Do not deploy if the scraper is failing — fix the issue first.
- **After making scraper/API changes**, monitor the next 2-3 scraper runs to confirm they complete successfully and stay within the GitHub API rate limit (5,000 req/hour). Current usage is ~800 calls/run at 12-min intervals (~4,000/hour max).

## Code Change Rules (any repo, including vets-api)
- **Before pushing any code change, always run the full local gates:** (1) the relevant specs — not just new/changed spec files, but specs for every touched code path; (2) linting (rubocop for Ruby) on the changed files AND confirm repo-wide lint config passes for anything new; (3) check the repo's CODEOWNERS file — every NEW file must have a matching CODEOWNERS entry (vets-api's "Check CODEOWNERS Entries" CI is a required check and fails otherwise); (4) review what other required CI checks the repo runs (Danger, security scans, etc.) and anticipate them locally where possible.

## PR Review Rules
- **Always check linked/companion PRs and cross-repo references during PR review.** If a PR description links related PRs (e.g., a vets-website companion, a gem/schema repo PR, or a linked issue), open and inspect them — verify what they actually change, whether they're merged, and how deploys are ordered/coordinated. For dependency bumps (e.g., vets-json-schema), diff the actual upstream revisions rather than trusting the bump's description. Never characterize a companion PR's contents without having read it.
- **Before every PR review**, reread the vets-api reverts report at `docs/notes/vets-api-reverts-report.md` in this repo to refresh awareness of common revert causes. Reverts are time-consuming and reflect poorly on the team — catching these patterns during review is critical.
- When reviewing a PR, check against these top revert causes (in order of frequency):
  1. **Dependency/gem upgrades (20%):** Does the PR bump a gem version? Check if it's a known problem gem (Rack, Datadog, karafka-core, Sentry). Verify the upgrade was tested in staging first.
  2. **Test failures (16%):** Does the PR modify or skip tests? Are specs updated for all affected code paths? Watch for `Sidekiq::Testing.disable!` cleanup issues and stale branch merges.
  3. **Production errors (15%):** Does the PR change auth flows, Redis caching, session handling, or external service integrations? These are the highest-impact revert causes.
  4. **Staging validation (11%):** Was the change tested in staging? Watch for column type mismatches, JSON serialization issues, and missing feature flags.
  5. **PII in logging:** Does the PR introduce or modify Sidekiq jobs? Verify PII is NOT passed as job arguments — must use `Sidekiq::AttrPackage` (cache key) or `KmsEncrypted::Box` (encrypted payload). Check all `Rails.logger` calls for SSN, email, name, ICN, file_number. See the PII section in the reverts report for full details.
  6. **Config changes:** Settings/config consolidation PRs have failed multiple times. Verify auth settings (`authn_requests_signed`) are preserved and all environments are tested.
  7. **Friday deployments:** Flag PRs merged late in the week that introduce risk. At least one revert was explicitly to avoid Friday deployment.

## Automatic Monitoring (Run on Every Prompt)
- On every prompt, check for CI/workflow failures using: `gh run list --limit=5`
- If any workflow shows "failure" status, automatically investigate and fix:
  1. Check the failure logs: `gh run view <run_id> --log`
  2. Identify the root cause (brakeman version, memory limits, timeouts, etc.)
  3. Apply the fix and push to trigger a new run
- Common failure patterns:
  - **CI exit code 5**: Brakeman version mismatch - update Gemfile.lock
  - **PR Scraper 502**: Memory exceeded on Render - reduce batch sizes or skip heavy operations
  - **PR Scraper timeout**: curl timeout too short - increase --max-time in workflow

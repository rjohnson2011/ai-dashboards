# Vets-API & Vets-API-Mockdata Revert Report

_Compiled from public revert PRs in department-of-veterans-affairs/vets-api. Author names removed for publication; every PR is linked so the full history is one click away._

**Period:** February 2025 – January 2026
**Total Reverts:** 85 (vets-api), 0 (vets-api-mockdata)

---

## Summary

| Category | Count | % |
|----------|-------|---|
| Dependency/gem upgrade broke production | 17 | 20% |
| Test failures on master (blocking deploys) | 14 | 16% |
| Production errors/outage | 13 | 15% |
| Staging failures / not ready for production | 9 | 11% |
| Feature flag / policy / business decision | 8 | 9% |
| Revert-of-revert (re-applying after fix) | 8 | 9% |
| Deployment/infrastructure failure | 5 | 6% |
| Accidental merge / premature deploy | 4 | 5% |
| Government shutdown hold | 2 | 2% |
| Other (CODEOWNERS, config, temporary testing) | 5 | 6% |

---

## vets-api-mockdata

**Zero reverts in the past year.** The most recent revert in this repo was PR #454 on February 8, 2024. This is a low-activity mock data repository with ~66 PRs merged in the past year.

---

## Detailed Revert List (vets-api)

### Dependency/Gem Upgrade Failures (17)

| PR | Date | Title | Reason |
| ---- | ------ | ------- | -------- |
| [#25849](https://github.com/department-of-veterans-affairs/vets-api/pull/25849) | 2026-01-07 | Revert "Downgraded aws-sdk-s3 to 1.203.1" | Reverted the downgrade itself |
| [#25698](https://github.com/department-of-veterans-affairs/vets-api/pull/25698) | 2025-12-19 | Revert "Prepend safe semantic logging monkey-patch" | Logging monkey-patch caused issues |
| [#25408](https://github.com/department-of-veterans-affairs/vets-api/pull/25408) | 2025-12-04 | Revert "Bump utf8-cleaner and rack" | Rack/utf8-cleaner bump caused issues |
| [#25327](https://github.com/department-of-veterans-affairs/vets-api/pull/25327) | 2025-11-25 | Revert "Bump sentry-ruby from 5.28.1 to 6.1.0" | Sentry events dropped from 55k/day to 1k/day after upgrade; breaking changes in sentry-ruby 6.x |
| [#25207](https://github.com/department-of-veterans-affairs/vets-api/pull/25207) | 2025-11-19 | Revert "Bump rack from 2.2.20 to 2.2.21" | Rack patch version broke production |
| [#24596](https://github.com/department-of-veterans-affairs/vets-api/pull/24596) | 2025-10-10 | Revert "Bump rack from 2.2.19 to 2.2.20" | Rack patch version broke production |
| [#24180](https://github.com/department-of-veterans-affairs/vets-api/pull/24180) | 2025-09-15 | Revert "Bump karafka-core from 2.5.5 to 2.5.6" | Version pinned temporarily due to rdkafka SSL issue |
| [#24085](https://github.com/department-of-veterans-affairs/vets-api/pull/24085) | 2025-09-11 | Revert "Bump karafka-core from 2.5.5 to 2.5.6" | Same karafka-core/rdkafka SSL cert issue |
| [#24018](https://github.com/department-of-veterans-affairs/vets-api/pull/24018) | 2025-09-09 | Revert "Bump datadog from 2.19.0 to 2.20.0" | Critical bug in libddwaf: `NoMethodError: undefined method 'length' for nil` on malformed query strings, causing 500 errors on all requests with `?&` patterns |
| [#23977](https://github.com/department-of-veterans-affairs/vets-api/pull/23977) | 2025-09-08 | Revert dependabot's waterdrop version bump | Waterdrop 2.8.6→2.8.7 caused SSL cert location errors in Kafka producer across dev/staging/sandbox |
| [#22578](https://github.com/department-of-veterans-affairs/vets-api/pull/22578) | 2025-06-06 | Revert "issue-110193-update-breakers-gem" | Breakers gem update caused issues |
| [#22375](https://github.com/department-of-veterans-affairs/vets-api/pull/22375) | 2025-05-23 | Revert "Bump datadog from 2.15.0 to 2.16.0" | New `on_error` handler warning in 2.16 causing floods of vets-api errors |
| [#20913](https://github.com/department-of-veterans-affairs/vets-api/pull/20913) | 2025-02-21 | Revert: Rack 3.0 upgrade | Auth missing cookies; middleware needs to move up in stack |
| [#20857](https://github.com/department-of-veterans-affairs/vets-api/pull/20857) | 2025-02-20 | Revert "Update to Rack 3.0.12" | Precautionary revert during Rack 3 upgrade investigation |
| [#20721](https://github.com/department-of-veterans-affairs/vets-api/pull/20721) | 2025-02-10 | Revert "Bump webmock from 3.24.0 to 3.25.0" | Possibly caused dev environment to go down |
| [#25557](https://github.com/department-of-veterans-affairs/vets-api/pull/25557) | 2025-12-12 | Revert "Add log_allowlist argument to Rails.logger" | Logger change caused issues |
| [#25660](https://github.com/department-of-veterans-affairs/vets-api/pull/25660) | 2025-12-18 | Revert "Disabled global HTTPI Debugging logging" | HTTPI logs being overridden by another gem (possibly caseflow) |

### Test Failures on Master / Blocking Deploys (14)

| PR | Date | Title | Reason |
| ---- | ------ | ------- | -------- |
| [#25689](https://github.com/department-of-veterans-affairs/vets-api/pull/25689) | 2025-12-19 | Revert "Remove mhv_medications_new_policy feature flag" | Causing failures in master; missing spec updates for new access policy |
| [#25462](https://github.com/department-of-veterans-affairs/vets-api/pull/25462) | 2025-12-08 | Revert "Burials HexaPDF compatibility updates (2 of 2)" | PDF fill spec failures: text truncated ("See" vs "See attachment") |
| [#25390](https://github.com/department-of-veterans-affairs/vets-api/pull/25390) | 2025-12-03 | Revert "2682/edipi bug" | No reason provided; reverted original PR |
| [#24797](https://github.com/department-of-veterans-affairs/vets-api/pull/24797) | 2025-10-24 | Revert "120475 674 bgs submission job" | Tests failing on master consistently since this commit |
| [#24599](https://github.com/department-of-veterans-affairs/vets-api/pull/24599) | 2025-10-10 | Revert "Profile - Add EmailVerificationJob" | Sidekiq tests failing in master; `Sidekiq::Testing.disable!` removed in after block |
| [#23544](https://github.com/department-of-veterans-affairs/vets-api/pull/23544) | 2025-08-13 | Revert "115118 background ocr fixes tempfile" | Based off 3-month-old branch, specs failing, interrupting deployment |
| [#23540](https://github.com/department-of-veterans-affairs/vets-api/pull/23540) | 2025-08-13 | Revert "Trying to fix some specs" | Spec fix attempt failed |
| [#23476](https://github.com/department-of-veterans-affairs/vets-api/pull/23476) | 2025-08-08 | Revert "fix: move SentryLogging deprecation warning" | CI test output too noisy, making it hard to identify failures |
| [#22969](https://github.com/department-of-veterans-affairs/vets-api/pull/22969) | 2025-07-07 | Revert "Skip Form21a flaky tests" | Flaky test skip was related to a schema issue now resolved |
| [#22057](https://github.com/department-of-veterans-affairs/vets-api/pull/22057) | 2025-05-06 | Revert "Replace Virtus with Vets::Model - Model Docs" | Sidekiq errors after Virtus model replacement |
| [#21040](https://github.com/department-of-veterans-affairs/vets-api/pull/21040) | 2025-03-03 | Revert "Single Config File - Settings - Attempt 2" | Second attempt at config consolidation also failed |
| [#21020](https://github.com/department-of-veterans-affairs/vets-api/pull/21020) | 2025-02-28 | Revert "Single Config File - Settings" | Config consolidation caused failures |
| [#21019](https://github.com/department-of-veterans-affairs/vets-api/pull/21019) | 2025-02-28 | Revert "remove authn_requests_signed from config settings" | Config removal broke authentication |
| [#20755](https://github.com/department-of-veterans-affairs/vets-api/pull/20755) | 2025-02-12 | Revert "staging data setup for accredited representative portal" | `ActiveRecord::RecordInvalid: Validation failed: Data does not comply with schema` on master |

### Production Errors/Outages (13)

| PR | Date | Title | Reason |
| ---- | ------ | ------- | -------- |
| [#26079](https://github.com/department-of-veterans-affairs/vets-api/pull/26079) | 2026-01-21 | Revert "Fix FeatureTogglesController Filter Chain Halting" | Production impact (no details provided) |
| [#26068](https://github.com/department-of-veterans-affairs/vets-api/pull/26068) | 2026-01-21 | Revert "Use MyHealth::FacilitiesHelper for mobile care system names" | Upstream not returning expected value |
| [#25560](https://github.com/department-of-veterans-affairs/vets-api/pull/25560) | 2025-12-12 | Revert "127436 cie travel claims logging/timeout adjustments" | Production issue (Slack thread reference) |
| [#24720](https://github.com/department-of-veterans-affairs/vets-api/pull/24720) | 2025-10-20 | Revert "RES/ch31 eligibility maintenance windows" | PagerDuty 403 errors: `BackendServiceException: {:status=>403}` |
| [#24664](https://github.com/department-of-veterans-affairs/vets-api/pull/24664) | 2025-10-15 | Revert "Reduce 296 Response Status for Users#show" | LOA1 and LOA3 users require different response structures |
| [#24461](https://github.com/department-of-veterans-affairs/vets-api/pull/24461) | 2025-09-30 | Revert "Adding date tests and pass through" | Sidekiq job failures during 526 form initial submission |
| [#24119](https://github.com/department-of-veterans-affairs/vets-api/pull/24119) | 2025-09-11 | Revert "118335 Update MHVJwtSessionClient redis caching" | **Major production issue** — Redis caching changes broke MHV JWT sessions |
| [#24110](https://github.com/department-of-veterans-affairs/vets-api/pull/24110) | 2025-09-11 | Revert healthcare cost and coverage | ArgoCD deployments failing in dev/staging/prod; improper RSA key parameter store configuration blocking 1pm production deployment |
| [#23792](https://github.com/department-of-veterans-affairs/vets-api/pull/23792) | 2025-08-26 | Revert breaking changes | Production errors (Slack thread reference) |
| [#23555](https://github.com/department-of-veterans-affairs/vets-api/pull/23555) | 2025-08-14 | Revert "115352 ep120 ep180 email notifications" | Caused an issue with an endpoint |
| [#23216](https://github.com/department-of-veterans-affairs/vets-api/pull/23216) | 2025-07-23 | Revert generating Oauth token in config | 401 errors in prod; token likely expiring when generated in config vs at request time |
| [#22274](https://github.com/department-of-veterans-affairs/vets-api/pull/22274) | 2025-05-19 | Revert "Replace Virtus with Vets::Model - Messages" | OOB (Out of Band) production ticket filed |
| [#22265](https://github.com/department-of-veterans-affairs/vets-api/pull/22265) | 2025-05-19 | Revert "Replace Virtus with Vets::Model - Prescriptions" | OOB production ticket filed |

### Staging Failures / Not Ready for Production (9)

| PR | Date | Title | Reason |
| ---- | ------ | ------- | -------- |
| [#25855](https://github.com/department-of-veterans-affairs/vets-api/pull/25855) | 2026-01-08 | Reverts adding UTC date to supporting docs | Release note requirement overlooked |
| [#25506](https://github.com/department-of-veterans-affairs/vets-api/pull/25506) | 2025-12-09 | Revert "Revise automated email to Pega for missing status" | Changes did not pass testing in staging |
| [#24377](https://github.com/department-of-veterans-affairs/vets-api/pull/24377) | 2025-09-25 | Revert "4759 upload supporting evidence" | Errors found in staging during testing |
| [#24368](https://github.com/department-of-veterans-affairs/vets-api/pull/24368) | 2025-09-24 | Revert small change | 500 error on staging not seen previously |
| [#24330](https://github.com/department-of-veterans-affairs/vets-api/pull/24330) | 2025-09-23 | Revert "Updating saved_claim to include user_account_id" | Need to change column type from BigInt to UUID first |
| [#23135](https://github.com/department-of-veterans-affairs/vets-api/pull/23135) | 2025-07-17 | Revert "[515] Add key to header for MHV Account Creation API" | Precautionary: created in case staging review results in errors |
| [#21476](https://github.com/department-of-veterans-affairs/vets-api/pull/21476) | 2025-03-28 | Revert "105513 Add applicants to metadata - form 10-10d" | JSON under applicant properties not properly stringified, causing form submission failures |
| [#21256](https://github.com/department-of-veterans-affairs/vets-api/pull/21256) | 2025-03-14 | Revert "fix: resolve form upload pdf stamping error" | (No specific reason provided) |
| [#21809](https://github.com/department-of-veterans-affairs/vets-api/pull/21809) | 2025-04-22 | Revert "Updating mobile prescriptions endpoint" | (No specific reason provided) |

### Feature Flag / Policy / Business Decision Reverts (8)

| PR | Date | Title | Reason |
| ---- | ------ | ------- | -------- |
| [#26185](https://github.com/department-of-veterans-affairs/vets-api/pull/26185) | 2026-01-27 | Reverts the PR for alternate names update | Business decision to revert |
| [#24969](https://github.com/department-of-veterans-affairs/vets-api/pull/24969) | 2025-11-17 | Revert changes related to 122512 | Removing changes for issue 122512 |
| [#23718](https://github.com/department-of-veterans-affairs/vets-api/pull/23718) | 2025-08-21 | Revert previous 10203 email additions | Code was fine but further business communication needed before deployment |
| [#23464](https://github.com/department-of-veterans-affairs/vets-api/pull/23464) | 2025-08-07 | Revert "DMT Remove SSN from prefill" | Backend needs SSN for backup path submissions |
| [#23428](https://github.com/department-of-veterans-affairs/vets-api/pull/23428) | 2025-08-07 | Reverting adding a rake task | No longer pursuing the rake task approach |
| [#23208](https://github.com/department-of-veterans-affairs/vets-api/pull/23208) | 2025-07-22 | Revert "Add vfs-10-10 to champva-engineering owned codeowners" | 1010 approval blocking current work; need different CODEOWNERS approach |
| [#22792](https://github.com/department-of-veterans-affairs/vets-api/pull/22792) | 2025-06-20 | Reverted datadog initializer to previous state | New datadog configuration did not impact dev/staging logs as expected |
| [#22765](https://github.com/department-of-veterans-affairs/vets-api/pull/22765) | 2025-06-20 | Revert change in CRM_ENV hash | UAT testing complete, reverting temporary config change |

### Revert-of-Revert (Re-applying After Fix) (8)

| PR | Date | Title | Reason |
| ---- | ------ | ------- | -------- |
| [#25695](https://github.com/department-of-veterans-affairs/vets-api/pull/25695) | 2025-12-22 | Revert "Revert "Remove mhv_medications_new_policy feature flag"" | Re-applying with fixed specs for v1 and v2 documentation |
| [#25148](https://github.com/department-of-veterans-affairs/vets-api/pull/25148) | 2025-11-17 | Revert^4 "RES/ch31 eligibility maintenance windows" | 4th revert in chain — yo-yo between applying and reverting |
| [#25131](https://github.com/department-of-veterans-affairs/vets-api/pull/25131) | 2025-11-17 | Revert^3 "RES/ch31 eligibility maintenance windows" | 3rd revert in chain |
| [#25127](https://github.com/department-of-veterans-affairs/vets-api/pull/25127) | 2025-11-14 | Revert^2 "RES/ch31 eligibility maintenance windows" | 2nd revert in chain (re-applying) |
| [#23107](https://github.com/department-of-veterans-affairs/vets-api/pull/23107) | 2025-07-15 | Revert "Revert "Console flipper error"" | Re-applying after investigating |
| [#22141](https://github.com/department-of-veterans-affairs/vets-api/pull/22141) | 2025-05-12 | Revert "Revert "VEBT-1702 - fix cert thru date logic"" | Approved to put code back; was unrelated to the issue being troubleshot |
| [#22135](https://github.com/department-of-veterans-affairs/vets-api/pull/22135) | 2025-05-20 | Revert "Disable Veteran::VSOReloader cron" | Upstream data issue resolved on May 14 |
| [#21897](https://github.com/department-of-veterans-affairs/vets-api/pull/21897) | 2025-04-25 | Revert "Revert "added encrypted_kms_key to submission tables"" | Fix found for `NameError: uninitialized constant` (case sensitivity in migration name) |

### Deployment/Infrastructure Failures (5)

| PR | Date | Title | Reason |
| ---- | ------ | ------- | -------- |
| [#21894](https://github.com/department-of-veterans-affairs/vets-api/pull/21894) | 2025-04-25 | Revert "added encrypted_kms_key to submission tables" | `db:migrate` failed in deployment |
| [#21539](https://github.com/department-of-veterans-affairs/vets-api/pull/21539) | 2025-04-02 | Revert "chore(PE): Add semver tag to vets-api docker image" | `Permission denied to github-actions[bot]` — 403 error pushing git tags |
| [#23542](https://github.com/department-of-veterans-affairs/vets-api/pull/23542) | 2025-08-13 | Revert "1584 remove stage 1 ff" | (No details — likely deploy-related given timing with other Aug 13 reverts) |
| [#20911](https://github.com/department-of-veterans-affairs/vets-api/pull/20911) | 2025-02-21 | Temp remove middleware to check auth | Debugging auth cookie issue during Rack 3 migration |
| [#24548](https://github.com/department-of-veterans-affairs/vets-api/pull/24548) | 2025-10-07 | Revert "Update JSON schema for appeal issues" | Branch accidentally deployed to production before testing |

### Government Shutdown Hold (2)

| PR | Date | Title | Reason |
| ---- | ------ | ------- | -------- |
| [#24424](https://github.com/department-of-veterans-affairs/vets-api/pull/24424) | 2025-09-29 | Revert "API-50205 - Update V2 FES mapper" | Reverting because merges to master on hold during potential government shutdown |
| [#24423](https://github.com/department-of-veterans-affairs/vets-api/pull/24423) | 2025-09-29 | Revert "API-47340 - Update v1 PDF uploads" | Same government shutdown hold |

### Other (CODEOWNERS, Config, Misc) (5)

| PR | Date | Title | Reason |
| ---- | ------ | ------- | -------- |
| [#25668](https://github.com/department-of-veterans-affairs/vets-api/pull/25668) | 2025-12-18 | Revert spec/factories/configurations.rb line in CODEOWNERS | Accidental CODEOWNERS change |
| [#23651](https://github.com/department-of-veterans-affairs/vets-api/pull/23651) | 2025-08-19 | Revert "Refactor BE Reviews" | (No details provided) |
| [#23104](https://github.com/department-of-veterans-affairs/vets-api/pull/23104) | 2025-07-15 | Revert "Console flipper error" | (No details provided) |
| [#22769](https://github.com/department-of-veterans-affairs/vets-api/pull/22769) | 2025-06-18 | Revert "Travel Pay / update default page size to 50" | (No details provided) |
| [#22661](https://github.com/department-of-veterans-affairs/vets-api/pull/22661) | 2025-06-12 | Revert "103352: Update persistent attachment logic" | (No details provided) |
| [#22663](https://github.com/department-of-veterans-affairs/vets-api/pull/22663) | 2025-06-12 | Revert "76592 fetch and mount certificate volume" | (No details provided) |
| [#20603](https://github.com/department-of-veterans-affairs/vets-api/pull/20603) | 2025-02-04 | Revert "EKS Locust load testing" | (No details provided) |
| [#23935](https://github.com/department-of-veterans-affairs/vets-api/pull/23935) | 2025-09-04 | Revert "API 49489 - Add Federal Activation obligation dates" | Don't want change going out on a Friday deployment |

---

## Notable Patterns

### 1. Dependency Upgrades Are the #1 Source of Reverts
17 of 85 reverts (20%) were caused by gem/dependency upgrades. Recurring offenders:
- **Rack** — reverted 4 times (2.2.19→2.2.20, 2.2.20→2.2.21, Rack 3.0, utf8-cleaner+rack)
- **Datadog** — reverted 3 times (2.15→2.16, 2.19→2.20, initializer config)
- **Karafka-core/waterdrop** — reverted 3 times (rdkafka SSL cert path issue)
- **Sentry-ruby** — reverted 1 time (5.28→6.1 dropped 98% of events)

### 2. Revert Chains
The **RES/ch31 eligibility maintenance windows** feature was reverted 4 times across PRs #24720 → #25127 → #25131 → #25148, indicating repeated failed attempts to land the feature.

The **Virtus → Vets::Model migration** required 3 separate reverts (Messages, Prescriptions, Model Docs) suggesting a systemic issue with the migration approach.

### 3. "No Reason Provided" is Common
~25 reverts had minimal or no explanation beyond "Reverts #XXXX". This makes it harder to learn from incidents.

### 4. Friday Deployment Avoidance
At least 1 revert (#23935) was explicitly to avoid deploying on a Friday, indicating a risk-averse deployment culture.

### 5. Monthly Distribution

| Month | Reverts |
|-------|---------|
| Jan 2026 | 5 |
| Dec 2025 | 10 |
| Nov 2025 | 6 |
| Oct 2025 | 6 |
| Sep 2025 | 10 |
| Aug 2025 | 10 |
| Jul 2025 | 5 |
| Jun 2025 | 6 |
| May 2025 | 6 |
| Apr 2025 | 4 |
| Mar 2025 | 4 |
| Feb 2025 | 6 |

September and August 2025 had the highest revert counts (10 each), possibly related to the Rack 3.0 migration effort and end-of-fiscal-year activity.

---

## PII Logging Risk — Critical Review Checkpoint

PII leaking into logs is one of the most severe risks in vets-api. While no PII-related reverts appeared in the past year, several production errors and Sidekiq job failures had the *potential* to expose PII if proper patterns weren't followed. Reviewers must verify PII handling on every PR that touches Sidekiq jobs, logging, or user data.

### How PII Leaks Happen in Sidekiq

When a Sidekiq job fails, its **arguments are logged** to the Sidekiq UI, Datadog, and Sentry. If PII (SSN, email, name, file number) is passed directly as a job argument, it becomes visible in error monitoring systems.

**Bad pattern (PII in job args):**
```ruby
# DON'T DO THIS — if the job fails, email and name appear in Datadog
EmailJob.perform_async(user.email, user.first_name, template_id)
```

### Two Approved Patterns for Sidekiq PII Protection

#### 1. `Sidekiq::AttrPackage` (Cache Key Pattern)
Store PII in Redis with a random key. Pass only the key to Sidekiq. On failure, only a hex string appears in logs.

```ruby
# Store PII in Redis
cache_key = Sidekiq::AttrPackage.create(
  expires_in: 7.days,
  email: user.email,
  first_name: user.first_name
)

# Only the cache key (random hex) is passed as a Sidekiq argument
NotificationJob.perform_async(template_type, cache_key)
```

The job retrieves PII at execution time:
```ruby
def perform(template_type, cache_key)
  data = Sidekiq::AttrPackage.find(cache_key)
  # ... use data[:email], data[:first_name] ...
  Sidekiq::AttrPackage.delete(cache_key)
end
```

**Used by:** `VANotify::V2::QueueEmailJob`, `EmailVerificationJob`, `EventBusGateway::LetterReadyEmailJob`, and others.

#### 2. `KmsEncrypted::Box` (Encrypted Payload Pattern)
For larger payloads (form submissions with participant_id, file_number, etc.), encrypt the entire payload before passing to Sidekiq.

```ruby
encrypted_payload = KmsEncrypted::Box.new.encrypt(payload.to_json)
SubmitFormJob.perform_async(claim_id, encrypted_payload)
```

**Used by:** `BPDS::Sidekiq::SubmitToBPDSJob`, `BGS::SubmitForm686cV2Job`, `BGS::SubmitForm674V2Job`.

### Other PII Protection Layers

| Layer | File | What It Does |
|-------|------|-------------|
| **Sentry Scrubber** | `lib/sentry/scrubbers/pii_sanitizer.rb` | Strips SSN, name, address, fileNumber from all Sentry events |
| **Rails Parameter Filter** | `config/initializers/filter_parameter_logging.rb` | Allowlist-based — everything NOT on the list is `[FILTERED]` |
| **Data Scrubber** | `lib/logging/helper/data_scrubber.rb` | Regex detection of SSN, email, ICN, EDIPI, credit card, VA file number |
| **PersonalInformationLog** | `app/models/personal_information_log.rb` | KMS-encrypted storage for debugging PII, auto-purged after 2 weeks |
| **Semantic Logger Patch** | `config/initializers/rails_semantic_logger_patch.rb` | Blocks `send_data` log events (PDF filenames can contain veteran names) |
| **BGS Error Override** | `lib/bgsv2/exceptions/bgs_errors.rb` | Overrides error messages that contain PII (e.g., CEST11 errors) |
| **Danger CI Check** | `lib/dangerfile/parameter_filtering_allowlist_checker.rb` | Warns on PRs that modify the parameter filter allowlist |
| **Appeals PII Cleanup** | `modules/appeals_api/app/sidekiq/appeals_api/clean_up_pii.rb` | Daily cron purges PII from processed appeal records |

### What to Watch for During PR Review

1. **New Sidekiq jobs:** Are PII values passed directly as `perform_async` arguments? They should use `Sidekiq::AttrPackage` or `KmsEncrypted::Box` instead.
2. **Logger calls:** Does `Rails.logger.info/warn/error` include user data? Check for SSN, email, name, ICN, file_number in log messages.
3. **Sentry/Datadog tags:** Are PII fields being added as custom tags or extra context?
4. **New API error responses:** Do error messages include PII from upstream services (e.g., BGS, MPI)?
5. **Parameter filter changes:** Any modification to `filter_parameter_logging.rb` is high-risk — `backend-review-group` is a CODEOWNER for this file.
6. **PDF/file operations:** Filenames derived from veteran data can leak PII in `send_data` events.

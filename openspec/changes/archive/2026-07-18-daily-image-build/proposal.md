## Why

The release image build in `build.yml` runs only once a week (Monday 10:00 UTC).
For a FIPS base image whose whole value is shipping current crypto and patched
OS/Beats packages, a weekly rebuild means up to six days of staleness — Alpine,
OpenSSL 3.5.x, and Beats fixes published mid-week aren't picked up until the next
Monday. The weekly-only cadence was a mistake; the image should rebuild **daily**
so it absorbs upstream patches within a day.

The constraint: the weekly CVE email to Elastic must **not** change. Today that
email is driven by the `schedule` event, so naively switching the cron to daily
would fire the report to Elastic every day. We need daily builds while keeping the
Elastic email (and its `cve-reports` commit) strictly weekly on Monday.

## What Changes

- `build.yml` schedule changes from a single weekly Monday cron to a daily cron,
  keeping the existing 10:00 UTC time (= 6am US Eastern during EDT). To avoid a
  Monday double-fire, this is expressed as two non-overlapping crons:
  - `'0 10 * * 1'` — Monday: build + scan + weekly Elastic email + `cve-reports` commit
  - `'0 10 * * 0,2-6'` — Sun, Tue–Sat: build + scan only
- The two already-gated steps (`Prepare and send weekly email report` and
  `Send email to Elastic`) change their gate from `github.event_name == 'schedule'`
  to `github.event.schedule == '0 10 * * 1'`, so the email + branch commit fire only
  on the Monday scheduled run. The `BEATS_CVE_TEST_EMAIL` test-mode clause is retained
  unchanged, so manual dry-runs still work on any day.
- The `build` and `beats-cve-report` jobs otherwise run every day: image build/push,
  ECR scan, beats filtering, and the GitHub Actions artifact upload all happen daily.
  The weekly email's week-over-week diff is unaffected because the `cve-reports`
  branch is still only committed on Monday, so each Monday still diffs against the
  previous Monday's dated report.
- `build-snapshot.yml` is intentionally left unchanged (stays weekly Monday, per the
  deliberate decision in commit `8ea1be7`). `build-snapshot-placeholder.yml` is
  untouched.

No new external dependencies, secrets, or repository variables. No change to email
content, recipients, subject, attachments, the diff logic, or the `cve-reports`
branch format.

## Capabilities

### New Capabilities
- `daily-image-build`: The release image is built and pushed on a daily schedule
  (10:00 UTC) in addition to push/PR/manual-dispatch triggers, using a two-cron
  structure that singles out the Monday run for weekly reporting. Capturing this as
  a requirement prevents a future revert of the cron back to weekly-only.

### Modified Capabilities
- `weekly-email-report`: The "Trigger Gating" requirement narrows from *any*
  `schedule` event to the **Monday** scheduled run (`'0 10 * * 1'`). The email and
  `cve-reports` commit steps SHALL run on the Monday schedule or in test mode, and
  SHALL be skipped on non-Monday scheduled runs (which still build and scan).

## Impact

- **Affected file**: `.github/workflows/build.yml` (schedule block + the `if:` on the
  two email/commit steps). No script changes.
- **Considered but unaffected**:
  - `daily-cve-scan` — the `beats-cve-report` job still runs after every successful
    build; daily builds simply make "after every build" a daily occurrence. No
    requirement change.
  - `cve-reports-branch` — filename format, `[skip ci]` hygiene, and retention are
    unchanged; the branch is just committed only on Mondays now (gating owned by
    `weekly-email-report`).
  - `build-snapshot.yml` and `build-snapshot-placeholder.yml` — out of scope.
- **Operational effect**: ~7× more scheduled runs (CI minutes, ECR pushes, run-number
  tags). Buildx local cache keeps incremental daily builds fast when no upstream
  versions changed. ECR `:<run-number>` tags accumulate faster — note for any image
  retention/lifecycle policy, but not changed here.
- **Jira**: IGDD-2982.

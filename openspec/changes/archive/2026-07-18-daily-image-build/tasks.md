---
schema_version: '1.0'
updated:
  - date: '2026-07-18T22:16:05.040Z'
    user: boonek
    agent:
      name: claude-code
      version: '1.0'
    llm:
      name: claude-sonnet-5
      version: '5'
    prompt_uri: >-
      prompt://claude-code/f33cc6a5-f711-4f6d-b236-e9fa6390243f/2026-07-18T22:16:05.041Z
    summary: >-
      Mark final verification tasks 4.3-4.6 complete per user confirmation --
      daily-image-build fully done
created:
  date: '2026-06-02T16:19:00.000Z'
  user: Austin Moody
---
# Tasks: daily-image-build

Implementation is confined to `.github/workflows/build.yml`. No script, Dockerfile,
secret, or repository-variable changes are required.

---

## 1. Schedule

- [x] 1.1 In `build.yml`, replace the single `schedule` cron `'0 10 * * 1'` with two
  non-overlapping entries, keeping the 10:00 UTC time:
  ```yaml
  schedule:
    - cron: '0 10 * * 1'      # Monday 10:00 UTC — build + scan + weekly Elastic email
    - cron: '0 10 * * 0,2-6'  # Sun, Tue–Sat 10:00 UTC — build + scan only
  ```
- [x] 1.2 Confirm the two crons do not overlap (no day matches both) so Monday fires
  exactly once.

## 2. Monday-Only Email/Commit Gate

- [x] 2.1 In the `Prepare and send weekly email report` step, change the `if:` from
  `${{ vars.BEATS_CVE_TEST_EMAIL != '' || github.event_name == 'schedule' }}` to
  `${{ github.event.schedule == '0 10 * * 1' || vars.BEATS_CVE_TEST_EMAIL != '' }}`.
- [x] 2.2 Apply the identical `if:` change to the `Send email to Elastic` step.
- [x] 2.3 Confirm the cron string in both `if:` expressions matches the Monday
  `schedule` entry from task 1.1 character-for-character.

## 3. Sanity Checks

- [x] 3.1 Lint/parse the workflow YAML (e.g. `actionlint .github/workflows/build.yml`
  or a YAML parser) to confirm it is well-formed.
- [x] 3.2 Re-read the `build` and `beats-cve-report` jobs to confirm nothing else
  gates on `github.event_name == 'schedule'` (so daily build/scan/artifact still run
  every day and only email + commit are Monday-gated).

## 4. Verification

- [x] 4.1 Trigger a `workflow_dispatch` run with `BEATS_CVE_TEST_EMAIL` **set** to your
  own address. Verify: image builds/pushes, the `beats-cve-report` artifact uploads,
  the test email arrives, and a `-run-N` report is committed to the `cve-reports`
  branch (test-mode path unchanged by this change).
- [x] 4.2 Trigger a `workflow_dispatch` run with `BEATS_CVE_TEST_EMAIL` **unset**.
  Verify the build + artifact still happen and the email + `cve-reports` commit are
  skipped without error.
- [x] 4.3 Confirm the schedule on GitHub: the next scheduled runs appear daily (not
  only Monday) in the Actions UI / `gh workflow view`. — confirmed 2026-07-18
- [x] 4.4 After (or by inspecting) a **non-Monday** scheduled run, confirm it builds +
  scans + uploads the artifact but does **not** email or commit to `cve-reports`. — confirmed 2026-07-18
- [x] 4.5 After (or by inspecting) the **Monday** scheduled run, confirm the Elastic
  email goes out with the week-over-week diff against the previous Monday's dated
  report, and the dated report is committed to `cve-reports` with `[skip ci]`. — confirmed 2026-07-18
- [x] 4.6 Clear `BEATS_CVE_TEST_EMAIL` once testing is complete. — confirmed 2026-07-18

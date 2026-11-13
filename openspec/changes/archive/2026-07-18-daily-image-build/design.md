## Context

`build.yml` currently runs on a single weekly cron (`'0 10 * * 1'`, Monday 10:00
UTC) plus push/PR/dispatch. The weekly cadence leaves the FIPS base image stale on
mid-week upstream patches. We want a daily build while keeping the Elastic CVE email
strictly weekly (Monday) — and today that email is gated on `github.event_name ==
'schedule'`, so a naive daily cron would email Elastic every day.

The whole change is confined to `build.yml`: the schedule block and the `if:`
condition on the two report/email steps. No script or Dockerfile changes.

## Goals / Non-Goals

**Goals:**
- Build + push + scan the release image daily at 10:00 UTC.
- Keep the Elastic email and the `cve-reports` commit Monday-only, with identical
  content, recipients, and week-over-week diff semantics.
- Preserve the `BEATS_CVE_TEST_EMAIL` manual dry-run path on any day.

**Non-Goals:**
- Changing `build-snapshot.yml` (stays weekly Monday per commit `8ea1be7`).
- Changing email content, recipients, the diff logic, or the `cve-reports` branch
  format.
- Adding a separate workflow file, ECR lifecycle/retention policy changes, or
  daylight-saving handling (cron stays UTC).

## Decisions

**Decision 1 — Express the schedule as two non-overlapping crons, not one daily cron.**
GitHub fires a workflow once per matching cron line. A single `'0 10 * * *'` plus a
Monday `'0 10 * * 1'` would *both* match on Monday and trigger two runs. So the
schedule is split into mutually exclusive lines:
- `'0 10 * * 1'` — Monday (the weekly report run)
- `'0 10 * * 0,2-6'` — Sunday + Tuesday–Saturday (build/scan only)

Together they cover all seven days with no overlap (cron day-of-week `0` and `6` are
Sun and Sat; `1` is Mon).
*Alternative considered:* one `'0 10 * * *'` cron plus a step that computes `date -u
+%u` to detect Monday. Rejected — it adds a moving part and a date dependency, and
`github.event.schedule` gives the same signal declaratively.

**Decision 2 — Gate the email/commit steps on `github.event.schedule == '0 10 * * 1'`.**
`github.event.schedule` is populated only for scheduled events and equals the exact
cron string that fired. This lets the existing `if:` stay a pure expression with no
date math:
`if: ${{ github.event.schedule == '0 10 * * 1' || vars.BEATS_CVE_TEST_EMAIL != '' }}`.
The `BEATS_CVE_TEST_EMAIL` clause is unchanged, so dispatch/push test runs behave
exactly as before. The cron string must match the schedule entry character-for-character.

**Decision 3 — Let the scan + artifact run daily; gate only email + commit.**
The `beats-cve-report` job (poll → retrieve → filter → upload artifact) is cheap and
runs every day; only the two reporting steps are Monday-gated. This keeps the diff
baseline clean: because the `cve-reports` commit happens only on Monday, each Monday
still diffs against the previous Monday's dated report — week-over-week semantics are
unchanged.

## Risks / Trade-offs

- **Cron-string drift** → If someone edits the Monday cron entry but not the `if:`
  expression (or vice versa), the email silently stops or starts firing daily. The
  `daily-image-build` spec records the exact strings; verification (below) exercises
  both a Monday and a non-Monday run.
- **DST** → 10:00 UTC is 6am ET only during EDT; in winter it is 5am ET. Accepted —
  GitHub cron is UTC-only and the exact local minute is not important for a build.
- **~7× more scheduled runs** → More CI minutes and faster-accumulating ECR
  `:<run-number>` tags. Buildx local cache keeps no-op daily builds fast; ECR
  retention is out of scope but worth a follow-up if tag count becomes an issue.
- **GitHub may skip scheduled runs under load / on inactive repos** → Inherent to
  Actions cron; unchanged by this design and acceptable for a daily rebuild.

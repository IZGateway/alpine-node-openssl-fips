## ADDED Requirements

### Requirement: Daily Build Schedule
The `build.yml` workflow SHALL build and push the release image on a daily
schedule at 10:00 UTC, in addition to its existing push, pull_request, and
workflow_dispatch triggers. This daily schedule replaces the previous
weekly Monday-only schedule (`'0 10 * * 1'`).

#### Scenario: Daily scheduled build
- **WHEN** the 10:00 UTC schedule fires on any day of the week
- **THEN** the `build` job builds the image and pushes it to ECR (`:<run-number>` and `:latest`) and ghcr.io (`:latest`)

#### Scenario: Mid-week upstream patch
- **WHEN** a new Alpine digest, OpenSSL 3.5.x release, or Beats release is published on a non-Monday
- **THEN** the next daily scheduled build picks it up within a day instead of waiting for the following Monday

### Requirement: Non-Overlapping Cron Entries
The daily schedule SHALL be expressed as two non-overlapping cron entries so
that exactly one scheduled run occurs per day and the Monday run is
distinguishable for weekly reporting: `'0 10 * * 1'` (Monday) and
`'0 10 * * 0,2-6'` (Sunday, Tuesday–Saturday). A single `'0 10 * * *'` cron
combined with a Monday cron SHALL NOT be used, because both would match on
Monday and trigger two runs.

#### Scenario: No Monday double-fire
- **WHEN** the schedule fires on Monday at 10:00 UTC
- **THEN** only the `'0 10 * * 1'` cron matches and the workflow runs exactly once

#### Scenario: Monday run is identifiable
- **WHEN** the workflow is triggered by the Monday schedule
- **THEN** `github.event.schedule` equals `'0 10 * * 1'`, allowing downstream steps to gate weekly-only behavior

#### Scenario: Non-Monday run is identifiable
- **WHEN** the workflow is triggered by the Sunday/Tuesday–Saturday schedule
- **THEN** `github.event.schedule` equals `'0 10 * * 0,2-6'`

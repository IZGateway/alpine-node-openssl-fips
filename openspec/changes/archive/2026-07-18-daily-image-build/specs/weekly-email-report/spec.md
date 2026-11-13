## MODIFIED Requirements

### Requirement: Trigger Gating
The email and cve-reports branch commit steps SHALL only execute on the weekly
Monday scheduled run (the cron `'0 10 * * 1'`), or when the repository variable
BEATS_CVE_TEST_EMAIL is set on a trigger where the beats-cve-report job runs
(test mode). Non-Monday scheduled runs (the cron `'0 10 * * 0,2-6'`),
workflow_dispatch, and push triggers SHALL skip these steps unless
BEATS_CVE_TEST_EMAIL is set. Pull requests remain excluded because the
beats-cve-report job is skipped for pull_request events. The gate SHALL be expressed as
`github.event.schedule == '0 10 * * 1'` rather than
`github.event_name == 'schedule'`, because the workflow now runs on a daily
schedule and only the Monday run is the weekly report.

#### Scenario: Monday schedule trigger
- **WHEN** the workflow is triggered by the Monday schedule (`github.event.schedule == '0 10 * * 1'`)
- **THEN** the email step executes and sends to production recipients, and the report is committed to the cve-reports branch

#### Scenario: Non-Monday schedule trigger
- **WHEN** the workflow is triggered by a non-Monday scheduled run (`github.event.schedule == '0 10 * * 0,2-6'`) and BEATS_CVE_TEST_EMAIL is not set
- **THEN** the build and beats-cve-report scan/artifact steps run, but the email and cve-reports branch-commit steps are skipped without error

#### Scenario: workflow_dispatch without test email
- **WHEN** the workflow is triggered by workflow_dispatch and BEATS_CVE_TEST_EMAIL is not set
- **THEN** the email and branch-commit steps are skipped without error

#### Scenario: Test mode
- **WHEN** BEATS_CVE_TEST_EMAIL is set on a non-pull_request trigger where the beats-cve-report job runs
- **THEN** the email step executes and sends to the address in BEATS_CVE_TEST_EMAIL

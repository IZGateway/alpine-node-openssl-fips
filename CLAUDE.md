# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo produces

A single Docker image — `alpine-node-openssl-fips` — bundling Alpine 3.23, Node 24
(Alpine's dynamically-linked build), a from-source build of OpenSSL 3.5.x configured
with the FIPS provider, and Elastic filebeat/metricbeat binaries. The image is the
base layer for FISMA-moderate IZ Gateway services that require a FIPS encryption module.

There is **no application code** here. The repo is the `Dockerfile`, GitHub Actions
workflows that build/scan/publish the image, and OpenSpec specs documenting those
workflows. There are no unit tests, linters, or `package.json` — the "test" is that
`docker build` succeeds and `openssl list -providers` shows the FIPS provider loaded.

## Build & verify

```bash
# Local build — resolves latest OpenSSL 3.5.x + latest Beats from upstream APIs at build time
docker build -t alpine-node-openssl-fips:dev .

# Pin versions (CI passes these; the Dockerfile falls back to API lookup when unset)
docker build \
  --build-arg OPENSSL_VERSION=<3.5.x> \
  --build-arg BEATS_VERSION_OVERRIDE=<x.y.z or x.y.z-SNAPSHOT> \
  -t alpine-node-openssl-fips:dev .

# Confirm the FIPS provider is active inside the image
docker run --rm alpine-node-openssl-fips:dev openssl list -providers
```

Don't hard-code version numbers in commits or PRs. The real version is whatever the
upstream APIs return at build time. There are two layers of fallback for API outages,
and neither is a real pin:
- **Dockerfile constants** in the `Falling back to known stable version ...` echo lines.
  They apply only when the build arg is empty (local builds and `build-snapshot.yml`).
  Bump them by hand when a new patch ships; see the `Update Dockerfile to support
  OpenSSL ...` commits.
- **Repo variables `FALLBACK_VERSION_OPENSSL` / `FALLBACK_VERSION_BEATS`** are used by
  `build.yml`'s version-resolve step. If the API lookup fails and the variable is unset,
  `build.yml` **fails the job** and does not fall through to the Dockerfile constant.

`APK_INDEX_HASH` (the sha256 of Alpine's `APKINDEX.tar.gz`, passed by `build.yml`) is
there only to bust the Docker layer cache when Alpine packages change. The
`echo "APK index hash: ..."` lines in both stages are what make it work, so don't remove them.

## Image architecture (`Dockerfile`)

Two-stage build. Understanding the FIPS wiring requires reading both stages plus
`openssl_fips_insert.txt` together:

1. **Stage 1 `openssl-build`** — Alpine + build deps. Downloads the OpenSSL 3.5.x source
   tarball from GitHub Releases (version from `OPENSSL_VERSION` arg or GitHub API),
   runs `./Configure enable-fips && make && make install`, copies `fips.so` into
   `/usr/lib/ossl-modules/`, generates `fipsmodule.cnf` via `openssl fipsinstall`, then
   uses an `awk` splice to replace the default commented-out `# fips = fips_sect` block
   in `/usr/local/ssl/openssl.cnf` with the active provider block from
   `openssl_fips_insert.txt`. The original config is preserved as `openssl.cnf.dist`.
2. **Stage 2** — Fresh Alpine. Installs `nodejs npm` plus operational packages
   (`nginx`, `dnsmasq`, `bind-tools`, `logrotate`, `curl`, `ca-certificates`, etc., some
   with version pins for CVE patches), copies `/usr/local` and `fips.so` from stage 1,
   then downloads filebeat + metricbeat tarballs. SNAPSHOT versions come from
   `snapshots.elastic.co`; released versions from `artifacts.elastic.co`.

**Key invariant:** both stages set `OPENSSL_FIPS=1` and
`LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64:/usr/lib/ossl-modules` so the OS
`openssl` CLI and the dynamically-linked `node` load the FIPS-enabled OpenSSL built in
stage 1, not Alpine's system OpenSSL. `openssl_fips_insert.txt` is the FIPS-only provider
config — editing it changes which providers the image loads by default.

## CI architecture (`.github/workflows/`)

All three workflows target AWS ECR + ghcr.io:

- **`build.yml`** — Production pipeline. Triggers: **daily** 10:00 UTC (two crons:
  `'0 10 * * 1'` Monday and `'0 10 * * 0,2-6'` other days), push to main, PRs to main,
  manual dispatch. Two jobs:
  - `build` — resolves component versions (Alpine digest, latest OpenSSL 3.5.x, latest
    Beats release), builds with buildx local cache (`.buildx-cache/`), pushes to
    `ghcr.io/izgateway/alpine-node-openssl-fips:latest` and ECR `:<run-number>` + `:latest`.
    Captures the installed Beats version by running `filebeat version` against the build.
  - `beats-cve-report` — skipped on PRs (no ECR push to scan). Polls ECR Enhanced Scan
    until ACTIVE, pulls findings, filters to `filebeat|metricbeat` packages via jq,
    generates JSON+CSV, diffs against the most recent dated report on the `cve-reports`
    branch, emails Elastic security on the Monday scheduled run only, and commits the
    report to `cve-reports`.
- **`build-snapshot.yml`** — Same shape as `build.yml` but weekly Mon 08:00 UTC
  (intentionally *before* the release build), targeting upcoming Beats SNAPSHOT versions
  (computed from the latest release, or the `snapshot_version` dispatch input). It passes
  only `BEATS_VERSION_OVERRIDE`, so OpenSSL is resolved inside the Dockerfile. It builds into
  ECR/ghcr repo `alpine-node-openssl-fips-snapshot` tagged `future-beats` (never `:latest`).
  Reports go to the `cve-reports-snapshot` branch (auto-created on first run).
- **`build-snapshot-placeholder.yml`** — Empty stub on `main`; keeps GitHub's UI happy.

### CVE pipeline scripts (`.github/scripts/`)

- `inspector-report.jq` — converts ECR enhanced-findings JSON to CSV rows. `--arg paths`
  is the filePath regex filter; `--arg cutoff` is a date filter (empty = no filter).
- `beats-cve-diff.sh` — prints CVE IDs in `current.json` absent from `baseline.json`
  (all current IDs if baseline is missing).
- `beats-cve-email.sh` — builds the HTML email body. Optional 6th positional arg is the
  label suffix the snapshot workflow passes ("SNAPSHOT").

### Trigger gating to remember

In `build.yml`, the email step and the cve-reports commit step run only when
`github.event.schedule == '0 10 * * 1'` **or** the repo variable `BEATS_CVE_TEST_EMAIL` is set.
The gate compares the literal cron string, so **if you edit the Monday cron, update both
`if:` gates to match**. Otherwise the weekly Elastic email silently stops, or fires every
day. Daily non-Monday runs build, scan, and upload artifacts only. `build-snapshot.yml`
still gates on `github.event_name == 'schedule'`, which is fine because it is weekly only.

To dry-run the email path on a manual dispatch, set `BEATS_CVE_TEST_EMAIL` to your own
address, then unset it. Without it, `workflow_dispatch` skips the email and the branch
commit. The `full_report` dispatch input skips the baseline diff and includes every
current CVE.

### Reports branch convention

`cve-reports` (release) and `cve-reports-snapshot` (snapshot) are **orphan** branches
holding only `reports/*.json` and `reports/*.csv`. Scheduled runs write
`beats-cve-YYYY-MM-DD.json`; manual dispatches append `-run-N` to avoid same-day
collisions. `beats-cve-latest.json/csv` is overwritten every run and is the diff fallback
when no dated baseline exists. Dated files are immutable; only `*-latest.*` is overwritten.
Every commit to these branches includes `[skip ci]`.

## OpenSpec workflow

This repo uses [OpenSpec](https://github.com/openspec-dev/openspec) (the `openspec` CLI)
for spec-driven changes to CI/CD behavior. Specs live in `openspec/specs/<capability>/spec.md`,
in-flight changes in `openspec/changes/<name>/`, archived under `openspec/changes/archive/`.
Three capabilities — `daily-cve-scan`, `weekly-email-report`, `cve-reports-branch` —
document the CVE pipeline the workflows implement. The `daily-image-build` change
(daily cron + Monday-only email gate) is already implemented in `build.yml`. Its remaining
tasks are post-deploy checks of real scheduled runs, and it has not been archived yet.

The `.github/skills/openspec-*/` directories are Claude Code skills driving the workflow,
exposed as `/opsx:new`, `/opsx:apply`, `/opsx:verify`, `/opsx:archive`, etc. (prompt
versions in `.github/prompts/opsx-*.prompt.md`). Use these rather than hand-editing
OpenSpec files when working on a change.

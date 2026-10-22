# pf2e

**Repository:** https://github.com/foundryvtt/pf2e
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `pf2e`)
- **Node strategy:** `node_version_lts_offset_months = 1`
- **Runners:** `jest`
- **Eras:** a single `test` command, always `jest`. No `test` script exists before 2020-04-22. From the earliest commits a `pretest` lint gate (`eslint`, later `npm run lint`) and a `posttest` betterer gate run around jest.

## Development style

- **PR merging strategy:** Transitioned (GitLab/CLI branch merges in 2021 → Squash and merge from mid-2022 onward).
- **Merge convention:** `Merge branch '<branch>' into 'master'` (2021); `<Title> (#<PR>)` (2022–2025, >99.6% from 2023 onward).
- **Direct commits:** Minimal (1.6% human direct commits, 296 commits).
- **JS/TS code impact of direct commits:** Negligible — system version banners, release notes, and minor styling hotfixes.
- **Issue tracking discipline:** High (community issues and PRs tracked on GitHub).
- **Workflow notes:** Migrated from GitLab local/branch merge workflow to GitHub web interface in mid-2022, enforcing near-100% Squash & Merge thereafter.

## Coverage collection

- **Suites collected:** `test`, with `--coverage` appended.
- **Suites excluded:** none.
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** runner coverage output is collected by `find-and-move-lcov.sh`.

## Checklist

- [x] 100 done (97/100)
- [x] failed tests doublechecked (49 exit-code-1 runs: 32 betterer quality-gate, 17 jest)
- [x] complete run (full history processed on committer date)
- [x] complete test failure check (all 68 failure fingerprints across 49 runs labeled)
- [x] complete JEV test failure check (68 fingerprints evaluated; 1 flagged runner_env_config failure audited as upstream defect in [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md))

## Results

Source: `stats_output/report.txt` (generated 2026-10-22 08:00).

| Metric | Value |
|---|---|
| Commits processed | 27992 |
| Without test failures | 27903 |
| With test failures | 49 |
| Not applicable | 0 |
| Hard errors | 40 |
| Coverage produced | 99.9% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py pf2e --stats` (window `min`, run 2026-10-22) and `stats_output/report.txt` (generated 2026-10-22 08:00). Labels: [`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv) (primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv) (diagnostic window). These CSVs are the single source of truth; this section reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 49 |
| Failing runs (label DB) | 49 (`failing runs` line) |
| Fingerprints (min / max) | 68 / 0 |
| Labeled fingerprints | 68 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 20 |
| reevaluated_acceptable | 13 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 35 |
| Manual / auto-propagated labels | 12 / 56 |
| Labeled detections (min) | 96/96 (100.0%) |
| Labeled runs (min) | 49/49 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 1 flagged row |
| Jev audit | current |

**State:** complete.

## Environment / setup fixes

None.

## Known gaps

Forty commits (0.14%) are hard errors: no `lcov.info` was produced. See [`output/`](output/) (`*.error`) and [`logs/`](logs/) (`*.error`) for the per-commit evidence.

| Signature | Count | Cause | Coverage impact | Action |
|---|---|---|---|---|
| `pretest` lint failure (`eslint` / `prettier`) — `npm ERR! Test failed` before jest runs | 37 | The commit's `pretest` lint gate exits non-zero, so `npm test` aborts before jest executes and no `lcov.info` is emitted (2021-02 to 2021-10) | none produced; commit uncollected | None. Developer-facing lint errors at those commits, not an environment artifact. |

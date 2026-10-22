# spreed

**Repository:** https://github.com/nextcloud/spreed
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `spreed`); `min_pm_version.npm = 8`.
- **Node strategy:** default.
- **Runners:** `jest`, `vitest`, `vue-cli-service`.
- **Eras:** `test:unit` used `vue-cli-service` initially and later `jest`. The `test`
  script replaced `test:unit` and moved from `jest` to `vitest`.

## Development style

- **PR merging strategy:** Merge commit (76.8% of first-parent commits).
- **Merge convention:** `Merge pull request #<PR> from <branch>`.
- **Direct commits:** Minimal human (0.2%, 12 commits); moderate bot (23.1%, 1,539 commits).
- **JS/TS code impact of direct commits:** Minimal — 23.1% direct commits are automated Transifex localization updates (`[l10n] Updated translations`); human direct commits are GitHub Actions workflow tweaks.
- **Issue tracking discipline:** High (Nextcloud pull request review process).
- **Workflow notes:** Clean merge-commit workflow for all functional code; translation bot commits directly to `main`.

## Coverage collection

- **Suites collected:** `test:unit`, then `test`. The runners are called directly with
  coverage parameters appended.
- **Suites excluded:** none.
- **Coverage tool / config:** runner-native coverage; the project does not use
  `testrunner` parameters.
- **LCOV production:** runner coverage output is collected by `find-and-move-lcov.sh`.

## Checklist

- [x] 100 done (92/100)
- [x] failed tests doublechecked (fails rarely)
- [x] complete run
- [x] complete test failure check (1,505 fingerprints: 1,229 acceptable, 276 reevaluated_acceptable, 0 problematic, 0 unclear)
- [x] complete JEV test failure check (automated System 1 labeling via Jev evaluated all 1,504 fingerprints; all 218 flagged problematic rows audited against git history in `label_analysis/jev_audit.md` and confirmed upstream developer regressions)

## Results

Source: `stats_output/report.txt` (generated 2026-10-22 08:54).

| Metric | Value |
|---|---|
| Commits processed | 16406 |
| Without test failures | 15875 |
| With test failures | 433 |
| Not applicable | 0 |
| Hard errors | 98 |
| Coverage produced | 99.4% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py spreed --stats` (window `min`, run 2026-10-22) and
`stats_output/report.txt` (generated 2026-10-22 08:54). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 433 |
| Failing runs (label DB) | 433 |
| Fingerprints (min / max) | 1505 / 1749 |
| Labeled fingerprints | 1505 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 1229 |
| reevaluated_acceptable | 276 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 22 / 1483 |
| Labeled detections (min) | 3422/3422 (100.0%) |
| Labeled runs (min) | 433/433 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 218 flagged rows |
| Jev audit | current ([`jev_audit.md`](label_analysis/jev_audit.md)) |

**State:** complete.

## Environment / setup fixes

- Removed unused `npm install -g nyc` from `install-and-run.sh` which previously failed on missing `electron-to-chromium` in Verdaccio tarball cache. 5 affected commits and 2 transient timeout commits re-ran successfully (archived in [`archive/fix_nyc_install/`](archive/fix_nyc_install/)).

## Known gaps

- **Author timestamp vs dependency release skew (62 commits):** Commits authored on long-lived branches requiring packages published after the author date (56 commits requiring `@vue/cli-service@^4.5.9+`, 5 commits requiring `vue-eslint-parser@^8.0.1`, and 1 commit requiring `@nextcloud/vue@^4.2.0`). Under the author-timestamp snapshotting policy ([`STUDY_DECISIONS.md §1`](../../STUDY_DECISIONS.md)), WayPack excludes post-author-date releases, causing `npm install --force` to skip them.

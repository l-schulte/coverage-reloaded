# moodleapp

**Repository:** https://github.com/moodlehq/moodleapp
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `moodleapp`).
  The `Angular compatibility` Node strategy is disabled.
- **Node strategy:** default.
- **Runners:** jest (dominant); a Karma (`ng test`) branch exists in
  `install-and-run.sh` but never fired in the collection window.
- **Eras:** the `unit` suite runs jest for the whole collection window (from
  2021-01). The `test` script changed from `jest --verbose` to
  `NODE_ENV=testing gulp && jest --verbose` (from 2021-02), so a Gulp step builds
  language/environment files before the tests from that point on. The `ng test`
  branch targets a single pre-window commit (around 2020-10).

## Development style

- **PR merging strategy:** Merge commit (98.5% of first-parent commits).
- **Merge convention:** `Merge pull request #<PR> from <branch>`.
- **Direct commits:** Negligible (0.4% human direct commits, 5 commits; 1.1% bot commits).
- **JS/TS code impact of direct commits:** Negligible — license updates (`[ci skip]`) and release build number bumps (`MOBILE-3783 release: Bump build numbers`).
- **Issue tracking discipline:** High (strictly mapped to Moodle JIRA issue tracker `MOBILE-<ID>` in branch names and commit descriptions).
- **Workflow notes:** Formal enterprise open-source workflow; zero squashed commits on `main`.

## Coverage collection

- **Suites collected:** `unit` (one suite, one `lcov` output).
- **Suites excluded:** none.
- **Coverage tool / config:** jest with the V8 coverage provider; the babel-based
  Istanbul provider crashes silently. Run as
  `jest --coverage --coverageProvider=v8 --coverageReporters=lcov --runInBand`.
- **LCOV production:** jest `lcov` reporter.

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked (non-zero-exit runs inspected and classified by failure family)
- [x] complete run (6607/6607 commits processed on author-date timestamps; 0 pending)
- [x] complete test failure check (all 116 failing runs labeled; 0 problematic/unclear)
- [x] complete JEV test failure check (Jev CSV present; [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md) is current)

## Results

Source: `stats_output/report.txt` (generated 2026-10-21 22:16).

| Metric | Value |
|---|---|
| Commits processed | 6607 |
| Without test failures | 6229 |
| With test failures | 116 |
| Not applicable | 152 |
| Hard errors | 110 |
| Coverage produced | 98.3% |

Full statistics and plots: [`stats_output/`](stats_output/).

### Zero-test runs (0.0 % coverage)

67 of the 116 failing runs executed no test at all: jest reported `Test Suites: <n>
failed, <n> total` with `Tests: 0 total`, because every suite failed to compile or
load before execution. Jest still writes a structurally valid `lcov` in that state —
measured on `1627386228_655e97213`: 1 736 `SF:` records and `LH=0` over
`LF=271964` — so these runs pass LCOV validation and enter the dataset as valid
partial coverage at exactly 0.0 % lines (the per-suite `min 0.0%` in
`report.txt`). They are the only population in this project with zero coverage.

Boundaries, sourced from `logs/`, `label_analysis/failure_labels_v2.db`, and
`git` in `repo/`:

- **Time:** first `2021-07-27 11:43` (`655e97213`), last `2025-09-26 11:00`
  (`d4ef8318e`). No zero-test run exists before 2021-07 or after 2025-09.
- **Branch:** all 67 are commits of merged side branches; **none lies on the
  first-parent mainline**. The 1 621 first-parent commits of `main` contain no
  failing run at all, so the mainline never carries this outlier.
- **Consecutiveness:** in processed (author-date) order the 67 form 23 bursts —
  13 isolated runs, 34 with a zero-test neighbour on both sides, 20 at a burst
  edge. The largest bursts are 25 runs (2023-11-28 14:56 → 11-30 14:06) and 10
  runs (2023-11-24 13:06 → 11-28 14:22), separated by single passing runs inside
  the 48-run Ionic 7 window.
- **Concentration:** 15 distinct pull-request branches; 44 of the 67 belong to
  ticket `MOBILE-3947` (three authors' branches), and 48 of the 67 fall between
  2023-11-09 and 2023-12-04.

| Era | Runs | Branch(es) | Signature |
|---|---|---|---|
| 2021-07-27 → 2021-08-09 | 8 | `MOBILE-3792-2`, `MOBILE-3833` | `TS2593` / `TS2304 Cannot find name 'fail'` — jest typings absent from the lockfile |
| 2022-03-01 | 1 | `MOBILE-3982` | `Could not locate module @singletons/components-registry` |
| 2023-04-21 | 1 | `MOBILE-4214` | `Jest encountered an unexpected token` on `@moodlehq/ionic-native-push` |
| 2023-11-09 → 2023-12-04 | 48 | `MOBILE-3947` (3 authors), `MOBILE-4479` | `TS2307` on `@ionic-native/qr-scanner/ngx` |
| 2024-03-18 | 1 | `MOBILE-4268` | `TS2353` object literal |
| 2024-09-19 → 2024-10-03 | 5 | `MOBILE-4660` | `TS2345` argument type |
| 2025-02-27 | 1 | `MOBILE-4549` | `TS2304 Cannot find name 'LongDateFormatKey'` |
| 2025-06-30 | 1 | `MOBILE-4739` | `TS2345` argument type |
| 2025-09-26 | 1 | `MOBILE-4842` | `TS2322` on `HTMLElement` union |

Every cause is upstream: the branch state was broken as authored and repaired
before or at merge, which is why no mainline commit is affected. The runs are
labeled `acceptable` / `reevaluated_acceptable`; the per-family attribution is in
[`label_analysis/jev_audit.md`](label_analysis/jev_audit.md). The zero coverage is
a property of the commit, not a pipeline defect: no execution occurred, so 0 % is
the correct measurement of what the suite exercised, but it is not evidence that
the code was untested.

## Failure triage

Source: `python check_failures_v2.py moodleapp --stats` (window `min`, run 2026-10-21)
and `stats_output/report.txt` (generated 2026-10-21 22:16). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section reports
numbers only and does not restate per-family labels. Automated System 1 labeling:
[`failure_labels_jev_min.csv`](label_analysis/failure_labels_jev_min.csv), audited in
[`jev_audit.md`](label_analysis/jev_audit.md).

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 116 |
| Failing runs (label DB) | 116 (`failing runs` line) |
| Fingerprints (min / max) | 70 / 72 |
| Labeled fingerprints | 70 (100%) |
| Unlabeled fingerprints | 0 |
| acceptable | 27 |
| reevaluated_acceptable | 43 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 14 / 56 |
| Labeled detections (min) | 259/259 (100%) |
| Labeled runs (min) | 116/116 (100%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 17 flagged rows (4 upstream defect families) |
| Jev audit | current |

**State:** complete. All failing runs are classified dev-facing or non-failures; no
`problematic` or `unclear` family remains, so no per-family table is given. The Jev
audit attributes all 17 flagged rows to commit-era upstream defects and requires no
pipeline change.

## Environment / setup fixes

- `--testTimeout=30000` added to the jest invocation in `install-and-run.sh`:
  component-render tests occasionally exceeded the 5000 ms default in the
  single-threaded container. Recovered 22 runs (failing runs 137 → 115) and
  eliminated the `CoreSitesProvider › adds ionic platform and theme classes`
  timeout family. A longer timeout cannot mask a genuine hang; two tests that
  never resolve still time out.
- V8 coverage provider used instead of the babel-based Istanbul provider, which
  crashes silently (see Coverage collection).

## Known gaps

- 67 failing runs executed zero tests and therefore carry 0.0 % coverage (see
  Zero-test runs under Results). They are genuine commit-era compile failures on
  merged side branches, not pipeline artifacts; no mainline commit is affected.
- 152 processed commits predate the test infrastructure and are recorded as
  **not applicable**.
- 110 hard errors (no coverage): 93 `npm install` failures — 69 on git-based
  `moodlemobile` Cordova dependencies (`git ls-remote`/HTTP errors for
  `phonegap-plugin-push`, `cordova-plugin-prevent-override`, and others) and 24
  registry version misses (`ETARGET`, e.g. `which-module@2.0.1`, `ws@8.16.0`) —
  15 runs where jest aborts with `Cannot find module 'ts-jest/utils'` and emits no
  LCOV, and 2 suite timeouts.
- Two true-hang tests cannot be recovered by raising the timeout (`Site Home link
  handlers` and `Credentials page › suggests contacting support` during the
  2023-09 login-restyling window). Both are dev-facing and transient.

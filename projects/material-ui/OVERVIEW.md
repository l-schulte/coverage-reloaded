# material-ui

**Repository:** https://github.com/mui/material-ui
**Status:** active

## Test infrastructure

- **Package manager:** npm, yarn, and pnpm across root and workspaces (see [`config.json`](../../config.json) → `material-ui`). The `pnpm-lock.yaml` Node strategy is disabled, and exact Node versions are used.
- **Node strategy:** `use_exact_node_version = true`; override `20.18` for `2025-08-05`–`2025-09-08` (epoch `1754389274`–`1757319331`).
- **Runners:** `jest`, `mocha`, `lerna`, `pnpm`, `vitest`.
- **Eras:** early commits run `jest` under `test`; intermediate commits run `mocha` wrapped in `nyc` via `test:coverage`; late commits run `vitest` with native v8 coverage. From 2024-02-14 to 2024-04-08 (402 commits) `test:coverage` ends in a broken `&& pnpm test:<pkg>` step whose root script name does not exist at those commits (see Known gaps).

## Development style

- **PR merging strategy:** Squash and merge (95.0% of first-parent commits).
- **Merge convention:** Strict `[<scope>] <Title> (#<PR>)`.
- **Direct commits:** Low (4.9% human direct commits, 483 commits).
- **JS/TS code impact of direct commits:** Negligible — direct commits are documentation copyedits, website UTM analytics parameters, and team sync scripts (`[docs] Fix use of ellipsis`, `[website] Remove Tidelift UTMs`).
- **Issue tracking discipline:** High (all features and fixes are issue-linked and PR-gated).
- **Workflow notes:** Extremely disciplined, automated CI and squash merge policy.

## Coverage collection

- **Suites collected:** `test:coverage` (wrapping `mocha` via `nyc`, or `vitest`).
- **Suites excluded:** the per-package `pigment` / `zero-runtime` suite that `test:coverage` chains after the `mocha` run is excluded from the `mocha` glob and runs without coverage instrumentation upstream; it contributes no LCOV in any era.
- **Coverage tool / config:** `nyc` (with babel registration) for `mocha` eras; native v8 provider for `vitest`.
- **LCOV production:** `nyc report --reporter=lcov` for mocha eras; direct LCOV export from `vitest`.

## Checklist

- [x] 100 done (95/100)
- [x] failed tests doublechecked
- [x] complete run (11,882 commits processed, 0 pending)
- [x] complete test failure check (1,286/1,286 failing runs labeled; 0 problematic/unclear)
- [x] complete JEV test failure check (29 flagged fingerprints audited; 0 pipeline defects; see [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md))

## Results

Source: `stats_output/report.txt` (generated 2026-10-21 21:53).

| Metric | Value |
|---|---|
| Commits processed | 11882 |
| Without test failures | 10258 |
| With test failures | 1286 |
| Not applicable | 0 |
| Hard errors | 338 |
| Coverage produced | 97.2% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py material-ui --stats` (window `min`, run 2026-10-21)
and `stats_output/report.txt` (generated 2026-10-21 21:53). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 1286 |
| Failing runs (label DB) | 1286 |
| Fingerprints (min / max) | 103 / 151 |
| Labeled fingerprints | 103 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 97 |
| reevaluated_acceptable | 6 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 18 / 85 |
| Labeled detections (min) | 13378/13378 (100.0%) |
| Labeled runs (min) | 1286/1286 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 29 flagged rows |
| Jev audit | current |

**State:** complete.

The 2026-10-21 pass added the `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL` detection
pattern and anchored the `FAIL\s` exclude to the line start in
[`label_analysis/failure_patterns.json`](label_analysis/failure_patterns.json),
which made 402 previously invisible failing runs detectable (884 → 1,286 runs).
The three resulting families are labeled through the shared auto rule
`703d68b079f4`. All 29 Jev-flagged fingerprints are attributed in
[`label_analysis/jev_audit.md`](label_analysis/jev_audit.md); none traces to the
container or harness.

## Environment / setup fixes

- **Pre-populate git tracking ref for `listChangedFiles`:**
  - `scripts/listChangedFiles.test.js` executes `git rev-parse origin/next` under `CIRCLECI=true`. In detached `HEAD`, this failed without network access.
  - Resolved in `install-and-run.sh` by populating local branch and remote-tracking refs: `git branch -f next HEAD` and `git update-ref refs/remotes/origin/next HEAD`.
  - The completed re-run eliminated ~2,081 exit code 1 failures, converting them into clean passes.
- **Node.js module detection override:**
  - On Node >= 20, `--no-experimental-detect-module` is exported in `NODE_OPTIONS` to prevent Node from parsing ambiguous CommonJS files as ECMAScript modules (ESM).
- **Headless browser bypass:**
  - `TEST_SCOPE=node` is exported in `install-and-run.sh` during the Vitest era to prevent tests from attempting to launch Playwright browser instances without container browser binaries.

## Known gaps

- **`pigment` / `zero-runtime` package suites not executed at 402 commits (2024-02-14 → 2024-04-08).** At those commits `test:coverage` ends in `&& pnpm test:zero-runtime`, `&& pnpm test:pigment-react`, or `&& pnpm test:pigment-css-react`, while only the `*:ci` variant exists in the root `package.json`; `pnpm` therefore exits with `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL`. The step is the last element of the chain, so nothing after it is skipped, and the `nyc` + `mocha` run plus the root LCOV complete before it. The chained step runs the package's uninstrumented `test` script (plain `mocha`, no `nyc`), and those paths are `--exclude`d from the `mocha` glob, so the collected LCOV is unaffected: no mocha-era LCOV contains `pigment`/`zero-runtime` files, no run directory holds a nested LCOV, and median line coverage in the window (90.4%) matches neighbouring commits (90.2%). The 402 runs are labeled `acceptable`. Upstream removed the broken tail on 2024-04-23; the chain only reaches it when the `mocha` run passes fully, which is why the failure does not extend past 2024-04-08.

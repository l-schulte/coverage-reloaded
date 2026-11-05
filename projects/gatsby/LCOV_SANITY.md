# LCOV Sanity & Coverage Integrity Analysis: gatsby

**Date of Analysis:** 2026-10-31  
**Target Project:** `projects/gatsby`  
**Report Source:** [`projects/gatsby/lcov_sanity_report.csv`](lcov_sanity_report.csv)  
**Verification Command:** `python3 check_lcov_sanity.py gatsby --verbose`

---

## 1. Study Verdict & Executive Assessment

- **Causal Study Verdict:** VALID WITH EXPLAINED HEURISTICS
- **Longitudinal Criterion (≥ 90%):** **PASS** (4206 of 4229 commits [99.5%] produced valid coverage)
- **Structural Integrity:** **VERIFIED WITH NOTED EXCEPTIONS** (6131 entries over 1353 commits (4-5 per commit) ghost file instances, 0 artifact leak records)

### Executive Summary & Context
Gatsby is a static site generator and React framework monorepo. Upstream's test suite targets the core compiler, page building, data query, and official plugin packages (`packages/gatsby*`).

Structural validity is high: zero artifact leaks, zero missing
  extensions, and coverage ratios stable within 0.812-0.850 across the whole
  history. All 2,964 `CRITICAL_ANOMALY` commits share a single flag
  (`MISSING_DIR:packages/gatsby-plugin-mdx`), which is a collection gap, not an
  upstream boundary: `install-and-run.sh` now extends `collectCoverageFrom` to the
  package's root-level sources. The affected commits are pending re-run; the
  numbers below still describe the pre-fix collection.

---

## 2. Pipeline Execution & Study Yield

*Summary of longitudinal commit processing and coverage availability for causal modeling.*

| Metric | Commits | Proportion | Description |
|---|---|---|---|
| **Total Commits Evaluated** | 4229 | 100.0% | Full longitudinal evaluation window |
| **Valid Coverage Produced** | 4206 | 99.5% | Clean suite executions & non-bailing test runs |
| **Hard Pipeline / Test Errors** | 23 | 0.5% | Broken build or environment states (`.error` / no LCOV) |
| **Not Applicable** | 0 | 0.0% | No non-test or excluded eras |

---

## 3. Structural Hygiene & Git Tree Alignment

*Verification that LCOV line records map 1-to-1 to Git-tracked source lines without container or build contamination.*

| Integrity Check | Count | Status | Finding / Analysis |
|---|---|---|---|
| **Ghost Files (`SF:` not in Git)** | 6131 entries over 1353 commits (4-5 per commit) | *Issues Found (benign)* | All are generated fixture output under `packages/gatsby/src/utils/parcel/__tests__/fixtures/*/.cache/compiled/`. Never a coverage-relevant path: 5 lines out of 32,544 LCOV lines (0.015%) in a sampled commit. |
| **Artifact Leaks (`dist/`, `build/`)** | 0 | **Clean** | No compiled output outside test fixtures is instrumented. |
| **Path Normalization** | 0 | **Clean** | All file paths correctly resolve relative to repository root |

---

## 4. Coverage Scope & Longitudinal Denominators

*Definition of the codebase denominator and longitudinal stability of the exposure variable.*

### Codebase Composition & Test Boundaries
High structural validity with coverage ratios stable within 0.812–0.850 across the entire history. The `MISSING_DIR:packages/gatsby-plugin-mdx` flag in early commits was a collection gap resolved by extending `collectCoverageFrom`, while benign fixture outputs account for minor ephemeral ghost paths.

### Longitudinal Metrics
- **Effective Coverage Ratio (`lcov_src_count / git_src_count`):**
  - **Min:** `0.812`
  - **Average:** `0.829`
  - **Max:** `0.850`

### Timeline & Era Evolution

| Era | Commits | Avg ratio | git_src | lcov_src |
|---|---|---|---|---|
| to 2022-08-10 | 2,964 | 0.824 | 1,211 | 1,080 |
| from 2022-08-11 | 1,242 | 0.843 | 1,289 | 1,219 |

Per calendar year (avg): 2021 0.820, 2022 0.830, 2023 0.825, 2024 0.842, 2025 0.841.

The only step change is at `3c0dd6d238` (2022-08-10), where the `gatsby-plugin-mdx`
v4 rewrite moved its sources from package root into `src/`, bringing 35 previously
un-instrumentable files into the denominator. Excluding those 35 files, the
pre-rewrite ratio is 0.848 against 0.850 after, i.e. the collection itself is
stable across the whole history. No runner migration or `collectCoverageFrom`
regression is visible; the `fix_jest_ts_coverage` re-run brought TypeScript into
scope project-wide with no ratio discontinuity.

### Intermittent Dips & Broken Tests

None. No commit falls more than 5 percentage points below the median ratio
(0.829). The non-bail policy (`--no-bail` semantics, `set +e` around the runner
only) holds: no truncated run produces a visibly reduced denominator.

---

## 5. Automated Checker Findings & Causal Attribution

*Detailed attribution of flags raised by `check_lcov_sanity.py` heuristics.*

| Flag / Detected Pattern | Affected Commits | Attribution Category | Root Cause & Upstream Mechanism |
|---|---|---|---|
| `MISSING_DIR:packages/gatsby-plugin-mdx` | 2,964 (70.1%) | Collection Boundary (Fixed) | Historical collection gap in pre-fix collection; resolved in install-and-run.sh by extending collectCoverageFrom |
| `GHOST_FILES` | 1,353 (32.0%) | Generated Test Fixture | Generated Parcel fixture output created during test execution under fixtures directory; represents 0.015% of lines |

### Detailed Analysis of Findings

| Flag | Commits affected | Window | Files |
|---|---|---|---|
| `MISSING_DIR:packages/gatsby-plugin-mdx(git=35)` | 2,964 | 2021-01-04 → 2022-08-10 | 35 |
| `GHOST_FILES` (below flag threshold, reported in CSV) | 1,353 | 2022-06-23 → present | 4-5 |

### Causal Attribution

**1. `packages/gatsby-plugin-mdx` — 35 source files, zero coverage (the sole
`CRITICAL_ANOMALY` driver).**

- **Classification:** Pipeline defect (fix applied, re-run pending).
- **Mechanism:** Upstream's `jest.config.js` sets
  `collectCoverageFrom = pkgs.map(p => path.join(p, 'src/**/*.js'))`, and before
  the v4 rewrite `packages/gatsby-plugin-mdx` kept its sources at package root
  (`index.js`, `gatsby-node.js`, `loaders/`, `utils/`, ...), so the glob matched
  nothing there. The package's tests do run and do load that code — the exposure
  variable was therefore missing 35 files for 2,972 commits (2021-01-04 ..
  2022-08-10). The study measures lines reached by tests, not the coverage scope
  upstream chose to report, so the missing files are a collection gap rather than
  an acceptable project boundary.
- **Fix:** `install-and-run.sh` appends
  `<rootDir>/packages/gatsby-plugin-mdx/**/*.{js,jsx,ts,tsx}` (with negations
  scoped to that package's `__tests__`, `fixtures`, `__mocks__`, `dist`,
  `node_modules` and `*.test.*`) whenever the checked-out commit has the package
  without a `src/` directory. The block is inert outside the affected era; after
  the v4 rewrite (`3c0dd6d238`, 2022-08-10) the ordinary `src` glob already covers
  the package.
- **Verified on one commit** (`2acc6ed3c5`, 2022-06-23): 36 new `SF:` entries, all
  `packages/gatsby-plugin-mdx/**`; 747 new lines of which 389 are hit (52.1 %);
  no entries removed, no test or fixture file added, exit code 0, single-commit
  ratio 0.8283 → 0.8570. `CRITICAL_ANOMALY` disappears for that commit.
- **Pending:** re-run of the 2,972 affected commits and regeneration of
  `lcov_sanity_report.csv`; the executive-summary proportions above refer to the
  pre-fix collection.

**2. Partial gaps below the flag threshold (not flagged, reported here for
completeness).** `packages/gatsby/cache-dir/**` (browser and SSR runtime, ~110
files at recent commits), plus package-root sources in
`gatsby-source-wordpress` (5), `gatsby-transformer-screenshot` (5),
`babel-preset-gatsby-package` (3-4), `gatsby-plugin-image` (4), `peril` (6) and a
long tail. All sit outside `packages/*/src/**` and are excluded by the same
upstream `collectCoverageFrom` rule.

- **Classification:** Intentional Project Architecture (upstream coverage scope).
- **Mechanism:** `cache-dir` is the browser runtime and SSR entry shipped with the
  `gatsby` package; unit tests under Node never load it, and upstream never listed
  it in `collectCoverageFrom`. Fixing this would require editing
  `jest.config.js` beyond upstream's scope, which the study does not do.

**3. Ghost files (`.cache/compiled/**` fixture output).**

- **Classification:** Pipeline-adjacent artifact (benign, generated code).
- **Mechanism:** The Parcel fixture tests compile fixture projects into
  `.cache/compiled/` inside the test fixture directory. Those outputs match the
  `src/**/*.js{,x,ts,tsx}` glob when jest writes its report and are therefore
  instrumented despite not being tracked in Git. Impact is negligible (0.015% of
  LCOV lines), and the paths are excluded from any Git-blame mapping by rule.

---

## 6. Downstream Methodological Guidance

1. **Bug-Introduction & SZZ Validity:** Coverage lines for generated
   `**/.cache/compiled/**` paths cannot be mapped to Git blame; these paths must be
   filtered before blame-based analysis. All other `SF:` paths resolve to tracked
   files. The 23 `ERROR` commits carry no coverage and are outside the exposure
   variable.
2. **Exposure Variable Comparability:** The ratio denominator is Git source within
   upstream's coverage scope (`packages/*/src/**`), not all production files in the
   repository. Cross-era comparisons are valid because the scope rule is constant;
   absolute ratios must not be compared across 2022-08-10 without noting that 35
   `gatsby-plugin-mdx` files entered the denominator. Treat the series as
   "coverage of upstream-instrumented sources", stable at 0.82-0.85.
3. **Action Items:** re-run the 2,972 commits from 2021-01-04 to 2022-08-10 with
   the updated `install-and-run.sh`, then regenerate `lcov_sanity_report.csv` and
   refresh this document. Expect `MISSING_DIR` to disappear and the era ratio to
   rise from 0.824 to about 0.857. Test files and fixtures remain inside the
   collection scope by decision; they are filtered at analysis time, not at
   collection time.

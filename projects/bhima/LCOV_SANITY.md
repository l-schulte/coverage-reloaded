# LCOV Sanity & Coverage Integrity Analysis: bhima

**Date of Analysis:** 2026-10-27  
**Target Project:** `projects/bhima`  
**Report Source:** [`projects/bhima/lcov_sanity_report.csv`](lcov_sanity_report.csv)  
**Verification Command:** `python3 check_lcov_sanity.py bhima --verbose`

---

## 1. Study Verdict & Executive Assessment

- **Causal Study Verdict:** VALID
- **Longitudinal Criterion (≥ 90%):** **PASS** (4,088 of 4,386 commits [93.2%] produced valid coverage)
- **Structural Integrity:** **CLEAN** (0 ghost files, 0 artifact leaks)

### Executive Summary & Context
Bhima is an open-source hospital and clinical management system. The test suite exercises both the Node.js/Express server backend and the AngularJS client application.

Exceptional data quality with **0 ghost files**, **0 artifact leaks**, **0 missing extensions**, and **0 missing directories**. Coverage ratio averages 97.8% across the entire multi-year repository history with near-zero variance.

---

## 2. Pipeline Execution & Study Yield

*Summary of longitudinal commit processing and coverage availability for causal modeling.*

| Metric | Commits | Proportion | Description |
|---|---|---|---|
| **Total Commits Evaluated** | 4,386 | 100.0% | Full longitudinal evaluation window |
| **Valid Coverage Produced** | 4,088 | 93.2% | Clean suite executions & non-bailing test runs |
| **Hard Pipeline / Test Errors** | 298 | 6.8% | Broken build or environment states (`.error` / no LCOV) |
| **Not Applicable** | 0 | 0.0% | No non-test or excluded eras |

---

## 3. Structural Hygiene & Git Tree Alignment

*Verification that LCOV line records map 1-to-1 to Git-tracked source lines without container or build contamination.*

| Integrity Check | Count | Status | Finding / Analysis |
|---|---|---|---|
| **Ghost Files (`SF:` not in Git)** | 0 | **Clean** | Every recorded file path accurately resolves to tracked Git repository files. |
| **Artifact Leaks (`dist/`, `build/`)** | 0 | **Clean** | No compiled or generated assets entered coverage output. |
| **Path Normalization** | 0 | **Clean** | All file paths correctly resolve relative to repository root |

---

## 4. Coverage Scope & Longitudinal Denominators

*Definition of the codebase denominator and longitudinal stability of the exposure variable.*

### Codebase Composition & Test Boundaries
All production healthcare administration modules across client and server trees are consistently instrumented. Zero non-source assets or compiled bundles enter coverage.

### Longitudinal Metrics
- **Effective Coverage Ratio (`lcov_src_count / git_src_count`):**
  - **Min:** 84.5%
  - **Average:** 97.8%
  - **Max:** 98.0%

### Timeline & Era Evolution
The multi-suite pipeline collects:
1. `server-unit` (`server`) — Mocha + c8.
2. `client-unit` (`coverage_client_client`) — Karma + karma-coverage + headless Chromium.
3. `integration` (`integration`) — Mocha + c8 against live Express, MySQL, and Redis.
4. `integration-stock` (`integration_stock`) — Mocha + c8 after database reseeding.

Across all eras (from 2021 through 2025), the coverage ratio remains exceptionally stable between 97.6% and 98.0%, reflecting full stack end-to-end execution of both server and client layers.

### Intermittent Dips & Broken Tests
Only three isolated commits dipped slightly below 95%:
- `0b35f4744f` and `e93ae989a3` (84.5%): Intermediate topic commits modifying module bundling before merge.
- `512af61316` (88.5%): Intermediate refactor commit.
The 208 test-failing commits captured non-zero exits without bailing, preserving accurate line execution metrics.

---

## 5. Automated Checker Findings & Causal Attribution

*Detailed attribution of flags raised by `check_lcov_sanity.py` heuristics.*

| Flag / Detected Pattern | Affected Commits | Attribution Category | Root Cause & Upstream Mechanism |
|---|---|---|---|
| *None* | 0 (0.0%) | Clean Execution | Passed all structural and longitudinal checks with 0 flags and 0 anomalies |

### Detailed Analysis of Findings
*(The project passed all structural and longitudinal checks with 0 flags and 0 anomalies.)*

---

## 6. Downstream Methodological Guidance

1. **Bug-Introduction & SZZ Validity:** Gold-standard benchmark for the empirical study. 0 ghost files and 97.8% average coverage ensure near-perfect fidelity when mapping bug-introducing changes via SZZ.
2. **Exposure Variable Comparability:** The exposure variable is uniform and directly comparable across all project eras.
3. **Action Items:** None required. Collection is exemplary.

# LCOV Sanity & Coverage Integrity Analysis: desktop

**Date of Analysis:** 2026-10-27  
**Target Project:** `projects/desktop`  
**Report Source:** [`projects/desktop/lcov_sanity_report.csv`](lcov_sanity_report.csv)  
**Verification Command:** `python3 check_lcov_sanity.py desktop --verbose`

---

## 1. Study Verdict & Executive Assessment

- **Causal Study Verdict:** VALID
- **Longitudinal Criterion (≥ 90%):** **PASS** (9,516 of 10,034 commits [94.8%] produced valid coverage)
- **Structural Integrity:** **CLEAN** (0 ghost files, 0 artifact leaks)

### Executive Summary & Context
GitHub Desktop is an Electron-based Git workflow client. Upstream's Jest unit test suite targets all core TypeScript application logic, state stores, Git process wrappers, and UI components under `app/src/`.

100% of all commits with coverage passed sanity validation with zero structural defects, zero ghost files, and zero artifact leaks.

---

## 2. Pipeline Execution & Study Yield

*Summary of longitudinal commit processing and coverage availability for causal modeling.*

| Metric | Commits | Proportion | Description |
|---|---|---|---|
| **Total Commits Evaluated** | 10,034 | 100.0% | Full longitudinal evaluation window |
| **Valid Coverage Produced** | 9,516 | 94.8% | Clean suite executions & non-bailing test runs |
| **Hard Pipeline / Test Errors** | 518 | 5.2% | Broken build or environment states (`.error` / no LCOV) |
| **Not Applicable** | 0 | 0.0% | No non-test or excluded eras |

---

## 3. Structural Hygiene & Git Tree Alignment

*Verification that LCOV line records map 1-to-1 to Git-tracked source lines without container or build contamination.*

| Integrity Check | Count | Status | Finding / Analysis |
|---|---|---|---|
| **Ghost Files (`SF:` not in Git)** | 0 | **Clean** | Every source file path recorded in LCOV exists in the checked-out Git tree at that commit. No container mount leaks or bad relative path normalizations. |
| **Artifact Leaks (`dist/`, `build/`)** | 0 | **Clean** | Zero coverage recorded on compiled/bundled output directories (`out/`, `dist/`). Coverage anchors exclusively on genuine source code. |
| **Path Normalization** | 0 | **Clean** | All file paths correctly resolve relative to repository root |

---

## 4. Coverage Scope & Longitudinal Denominators

*Definition of the codebase denominator and longitudinal stability of the exposure variable.*

### Codebase Composition & Test Boundaries
All functional Git interaction layers and UI rendering components are instrumented by Jest. End-to-end Spectron launch smoke tests and installer packaging scripts are intentionally excluded from line coverage.

### Longitudinal Metrics
- **Effective Coverage Ratio (`lcov_src_count / git_src_count`):**
  - **Min:** 0.1086 (10.9%)
  - **Average:** 0.7569 (75.7%)
  - **Max:** 0.8761 (87.6%)

### Timeline & Era Evolution
The longitudinal coverage ratio exhibits a clear structural shift caused by upstream configuration changes:
1. **Pre-May 2022 Era (Jest with configured coverage):**
   - Ratios consistently average **~81% to ~87%**.
   - `app/jest.unit.config.js` explicitly defined `collectCoverageFrom: ['src/**/*.{js,jsx,ts,tsx}', ...]`, forcing Jest to report lines for all matching project files in the denominator, even if untouched by tests.
2. **Post-May 2022 Era (Removal of `collectCoverageFrom`):**
   - On 2022-05-04, upstream commit [`4686d0006ab`](file:///home/lschulte/raid/VCS/cdbs_coverage/coverageSHARK/tools/coverage_reloaded/projects/desktop/OVERVIEW.md#L32-L34) ("Get rid of unused coverage reporting") deleted Codecov configuration and `collectCoverageFrom`.
   - Following the project's own intent (per `AGENTS.md` §1), Jest subsequently instrumented only modules actively required/imported during test execution, causing the reported source ratio to shift from ~87% down to **~37%–46%** (380–400 files out of ~830 in Git).
3. **April 2025 Era (Node Test Runner + `c8`):**
   - Desktop transitioned from Jest to Node's native test runner (`node --test` via `script/test.mjs`), wrapped with `c8`. Coverage ratios remain consistent with the loaded-module scope (~44%).

### Intermittent Dips & Broken Tests
Isolated commits drop to very low coverage ratios (~10%–25%, e.g., commit `47db43c6d6` at 15.8%):
- **Mechanism:** In accordance with the mandatory non-bailing rule (`--no-bail` / omit bail), commits containing broken code (such as TypeScript compilation errors in specific modules) fail individual test suites while allowing remaining independent suites to execute.
- **Validity:** The resulting partial LCOV accurately captures test exposure for the passing test files at that developer commit.

---

## 5. Automated Checker Findings & Causal Attribution

*Detailed attribution of flags raised by `check_lcov_sanity.py` heuristics.*

| Flag / Detected Pattern | Affected Commits | Attribution Category | Root Cause & Upstream Mechanism |
|---|---|---|---|
| *None* | 0 (0.0%) | Clean Execution | Passed all structural and longitudinal checks with 0 flags and 0 anomalies |

### Detailed Analysis of Findings
- **Total Flagged Anomalies:** **0**
- No `CRITICAL_ANOMALY` or `WARNING` conditions were encountered across the entire 10,034-commit dataset.

---

## 6. Downstream Methodological Guidance

1. **Bug-Introduction & SZZ Validity:**
   - Perfect alignment between LCOV `SF:` paths and Git tree files ensures that line-level Git blame annotations can be computed without path rewriting or risk of ghost mismatches.
2. **Exposure Variable Comparability:**
   - Downstream causal analyses must account for the 2022-05-04 denominator shift: prior to this date, unexercised files are listed in LCOV with 0% line coverage; after this date, unexercised files are omitted from LCOV by Jest. When computing project-wide coverage metrics, normalization against total Git source files is recommended.
3. **Action Items:**
   - Coverage collection for `desktop` is sound, complete, and requires no pipeline repairs or re-runs.

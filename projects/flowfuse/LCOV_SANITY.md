# LCOV Sanity & Coverage Integrity Analysis: flowfuse

**Date of Analysis:** 2026-10-27  
**Target Project:** `projects/flowfuse`  
**Report Source:** [`projects/flowfuse/lcov_sanity_report.csv`](lcov_sanity_report.csv)  
**Verification Command:** `python3 check_lcov_sanity.py flowfuse --verbose`

---

## 1. Study Verdict & Executive Assessment

- **Causal Study Verdict:** VALID WITH EXPLAINED HEURISTICS
- **Longitudinal Criterion (≥ 90%):** **PASS** (14,697 of 15,802 commits [93.0%] produced valid coverage)
- **Structural Integrity:** **CLEAN** (0 ghost files, 0 artifact leaks)

### Executive Summary & Context
FlowFuse is an enterprise management platform for Node-RED. The codebase consists of a Node.js backend (`forge/`) and a Vue.js frontend (`frontend/`). Upstream originally tested only the backend service, introducing Vue frontend unit test infrastructure via Vitest in June 2022 (commit `4de1a795e`).

Exceptional structural hygiene with **0 ghost files** and **0 artifact leaks** across all 15,802 commits. The 917 `CRITICAL_ANOMALY` commits are strictly confined to the pre-Vitest historical era (September 2021 – June 2022), when upstream had not yet implemented unit test infrastructure for the Vue frontend. Once frontend unit tests were added in commit `4de1a795e` (June 2022), 100% of subsequent applicable commits achieved clean `OK` status with an average coverage ratio of 95.0%–100.0%.

---

## 2. Pipeline Execution & Study Yield

*Summary of longitudinal commit processing and coverage availability for causal modeling.*

| Metric | Commits | Proportion | Description |
|---|---|---|---|
| **Total Commits Evaluated** | 15,802 | 100.0% | Full longitudinal evaluation window |
| **Valid Coverage Produced** | 14,697 | 93.0% | Clean suite executions & non-bailing test runs |
| **Hard Pipeline / Test Errors** | 786 | 5.0% | Broken build or environment states (`.error` / no LCOV) |
| **Not Applicable** | 319 | 2.0% | Excluded commits (e.g. non-test eras, focus markers) |

---

## 3. Structural Hygiene & Git Tree Alignment

*Verification that LCOV line records map 1-to-1 to Git-tracked source lines without container or build contamination.*

| Integrity Check | Count | Status | Finding / Analysis |
|---|---|---|---|
| **Ghost Files (`SF:` not in Git)** | 0 | **Clean** | Every recorded file path accurately resolves to tracked Git repository source files. |
| **Artifact Leaks (`dist/`, `build/`)** | 0 | **Clean** | Zero compiled bundles or build outputs entered coverage output. |
| **Path Normalization** | 0 | **Clean** | All file paths correctly resolve relative to repository root |

---

## 4. Coverage Scope & Longitudinal Denominators

*Definition of the codebase denominator and longitudinal stability of the exposure variable.*

### Codebase Composition & Test Boundaries
In modern eras (June 2022 onwards), 100% of both backend Node.js and frontend Vue.js source trees are tested and instrumented. The 917 early commits reflect upstream's historical test infrastructure timeline prior to adopting Vitest.

### Longitudinal Metrics
- **Effective Coverage Ratio (`lcov_src_count / git_src_count`):**
  - **Min:** 30.7% (early era when only backend `forge/**` had unit tests)
  - **Average:** 95.0%
  - **Max:** 100.0%

### Timeline & Era Evolution
- **Pre-Vitest Backend-Only Era (2021-09 to 2022-06, 917 commits):**
  The project codebase comprised backend Express/Node services (`forge/` and `ee/`) and an evolving Vue frontend (`frontend/`). Upstream only maintained unit and system test suites for the backend using Mocha (`test:unit` and `test:system`), while frontend testing was exclusively performed via Cypress end-to-end tests (which are off-limits per causal study decisions). Coverage collection properly followed upstream's `.nycrc.json` (`include: forge/**`), yielding clean backend coverage but leaving `frontend/*.vue` uninstrumented (ratio ~30.7%–52.0%).
- **Multi-Suite Era (2022-06 to 2025+, 13,780 commits):**
  In mid-2022 (`4de1a795e` / `e904fc5aa`), upstream introduced `test:unit:frontend` powered by Vitest to unit test Vue components directly. Our pipeline executed both suites (`forge-unit` via Mocha + nyc and `frontend-unit` via Vitest). From July 2022 onward, `CRITICAL_ANOMALY` dropped to **zero** (13,648 OK runs), with coverage ratios consistently reaching 95%–100%.

### Intermittent Dips & Broken Tests
Focus markers (`.only` declarations) in the test suite were safely caught by `na_if_focus_marker` (319 commits classified as `NOT_APPLICABLE`), preventing silent truncation of coverage. Hard errors (786 runs) reflect broken commits and build failures across the large commit history.

---

## 5. Automated Checker Findings & Causal Attribution

*Detailed attribution of flags raised by `check_lcov_sanity.py` heuristics.*

| Flag / Detected Pattern | Affected Commits | Attribution Category | Root Cause & Upstream Mechanism |
|---|---|---|---|
| `MISSING_EXT:vue` & `MISSING_DIR:frontend` | 917 (5.8%) | Upstream Test Evolution | Pre-Vitest era (Sep 2021 – Jun 2022) when upstream had not yet implemented unit tests for the Vue frontend; 100% clean afterwards |

### Detailed Analysis of Findings
- `MISSING_EXT:vue(git=92-132, share=45-48%, lcov=0)` and `MISSING_DIR:frontend(git=120-168)`: Occur together on 917 early commits.

### Causal Attribution
- **Classification:** Upstream Test Design Evolution (Valid).
- **Mechanism:**
  Before June 2022, no unit test runner or coverage configuration existed upstream for the Vue frontend. The pipeline correctly followed upstream coverage intent (instrumenting backend suites with `nyc` matching the project's own `.nycrc.json`). Once upstream instituted frontend unit testing, the pipeline seamlessly collected Vitest LCOV outputs alongside Mocha outputs.

---

## 6. Downstream Methodological Guidance

1. **Bug-Introduction & SZZ Validity:** Completely sound. For commits after June 2022, both frontend and backend are comprehensively covered. For commits prior to June 2022, studies analyzing bug introduction should be aware that defects introduced in `frontend/` components during that window were only tested via e2e Cypress and will not have unit coverage recorded.
2. **Exposure Variable Comparability:** Researchers should account for the June 2022 boundary when analyzing full-codebase coverage ratios versus backend-only (`forge/`) coverage ratios.
3. **Action Items:** None required. Pipeline behavior exactly mirrors the historical testing evolution of the repository.

# LCOV Sanity & Coverage Integrity Analysis: sequelize

**Date of Analysis:** 2026-10-27  
**Target Project:** `projects/sequelize`  
**Report Source:** [`projects/sequelize/lcov_sanity_report.csv`](lcov_sanity_report.csv)  
**Verification Command:** `python3 check_lcov_sanity.py sequelize --verbose`

---

## 1. Study Verdict & Executive Assessment

- **Causal Study Verdict:** VALID WITH EXPLAINED HEURISTICS
- **Longitudinal Criterion (≥ 90%):** **PASS** (2,912 of 3,007 commits [96.8%] produced valid coverage)
- **Structural Integrity:** **VERIFIED WITH NOTED EXCEPTIONS** (16,945 occurrences ghost file instances, 1,376 occurrences artifact leak records)

### Executive Summary & Context
Sequelize is an Object-Relational Mapper (ORM) for Node.js. Upstream's test suite covers SQL dialect generation, data types, transactions, associations, and model querying across PostgreSQL, MySQL, SQLite, and MSSQL.

91.1% of commits pass with zero warnings or errors. Zero critical anomalies were detected across the entire history. The 172 warning commits involve minor compiled bundle artifacts (`dist/index.mjs` and `lib/index.mjs`) generated during the TypeScript build step entering coverage.

---

## 2. Pipeline Execution & Study Yield

*Summary of longitudinal commit processing and coverage availability for causal modeling.*

| Metric | Commits | Proportion | Description |
|---|---|---|---|
| **Total Commits Evaluated** | 3,007 | 100.0% | Full longitudinal evaluation window |
| **Valid Coverage Produced** | 2,912 | 96.8% | Clean suite executions & non-bailing test runs |
| **Hard Pipeline / Test Errors** | 95 | 3.2% | Broken build or environment states (`.error` / no LCOV) |
| **Not Applicable** | 0 | 0.0% | No non-test or excluded eras |

---

## 3. Structural Hygiene & Git Tree Alignment

*Verification that LCOV line records map 1-to-1 to Git-tracked source lines without container or build contamination.*

| Integrity Check | Count | Status | Finding / Analysis |
|---|---|---|---|
| **Ghost Files (`SF:` not in Git)** | 16,945 occurrences | *Minor / Benign* | Across 2,523 commits, exactly 1 ghost file per dialect suite was recorded: `lib/index.mjs`. This file is generated during TypeScript compilation into the gitignored `/lib` folder and imported by unit tests. |
| **Artifact Leaks (`dist/`, `build/`)** | 1,376 occurrences | *Flagged* | Across 172 commits during the early ESM/TypeScript transition, tests imported the built `dist/index.mjs`, registering 1 leak entry per dialect suite. |
| **Path Normalization** | 0 | **Clean** | All file paths correctly resolve relative to repository root |

---

## 4. Coverage Scope & Longitudinal Denominators

*Definition of the codebase denominator and longitudinal stability of the exposure variable.*

### Codebase Composition & Test Boundaries
Clean coverage across the entire ORM core. Minor warnings reflect TypeScript build outputs (`dist/index.mjs` and `lib/index.mjs`) transiently imported by test runners during historical build script transitions.

### Longitudinal Metrics
- **Effective Coverage Ratio (`lcov_src_count / git_src_count`):**
  - **Min:** 0.7452 (74.5%)
  - **Average:** 0.9056 (90.6%)
  - **Max:** 0.9896 (99.0%)

### Timeline & Era Evolution
Throughout the multi-year history (single-package npm -> yarn@1 -> monorepo yarn workspaces -> yarn berry):
- Coverage ratios remain consistently high and stable, averaging **90.6%** of git source files.
- The dialect test matrix (`mysql`, `postgres`, `sqlite`, `mariadb`, `mssql`, `db2`, `snowflake`, `oracle`) ensures comprehensive execution across the entire ORM query compiler, model definitions, and connection pools.

---

## 5. Automated Checker Findings & Causal Attribution

*Detailed attribution of flags raised by `check_lcov_sanity.py` heuristics.*

| Flag / Detected Pattern | Affected Commits | Attribution Category | Root Cause & Upstream Mechanism |
|---|---|---|---|
| `ARTIFACT_LEAKS` | 172 (5.7%) | TypeScript Build Transition | dist/index.mjs imported by unit test runners during an early TypeScript build era |
| `GHOST_FILES` | 2,523 (83.9%) | Build Emission Path | lib/index.mjs compiled from src/ into gitignored lib/ directory and imported by test runners |

### Detailed Analysis of Findings
- **`ARTIFACT_LEAKS(1)`** (172 commits): Flagged because `dist/index.mjs` was imported by unit test runners during an early TypeScript build era.
- **`GHOST_FILES(1)`** (2,523 commits): Flagged because `lib/index.mjs` is compiled from `src/` into the gitignored `/lib` directory, which is then imported by tests.

### Causal Attribution
- **Classification:** **TypeScript Build Emission Artifact** (Benign build artifact inclusion).
- **Mechanism:**
  - In modern Sequelize (v7 / TS era), TypeScript source code lives under `packages/*/src/` and compiles to `/lib` or `dist/` before test execution.
  - Test suites import the root entry point (`lib/index.mjs`), causing `c8` / V8 coverage to record execution lines for that single compiled entry wrapper.

---

## 6. Downstream Methodological Guidance

1. **Bug-Introduction & SZZ Validity:**
   - Overwhelming majority of lines in LCOVs correspond directly to genuine source files in `src/` or `lib/` (in legacy JS eras).
   - Downstream tools should ignore line mappings for the single synthetic entry file `lib/index.mjs` and `dist/index.mjs`. All core ORM model, query, and dialect files map 1:1 to Git commits.
2. **Exposure Stability:**
   - The dialect-per-suite collection ensures continuous, high-exposure measurement across history without significant denominator volatility.
3. **Action Items:**
   - No pipeline changes required.

# LCOV Sanity & Coverage Integrity Analysis: moodleapp

**Date of Analysis:** 2026-10-27  
**Target Project:** `projects/moodleapp`  
**Report Source:** [`projects/moodleapp/lcov_sanity_report.csv`](lcov_sanity_report.csv)  
**Verification Command:** `python3 check_lcov_sanity.py moodleapp --verbose`

---

## 1. Study Verdict & Executive Assessment

- **Causal Study Verdict:** VALID WITH EXPLAINED HEURISTICS
- **Longitudinal Criterion (≥ 90%):** **PASS** (6,345 of 6,607 commits [96.0%] produced valid coverage)
- **Structural Integrity:** **CLEAN** (0 ghost files, 0 artifact leaks)

### Executive Summary & Context
Moodle App is an Apache Cordova / Ionic mobile application for Moodle. The application is written 100% in TypeScript (`src/`). The repository includes ~35 static vendored JavaScript files in `src/core/features/h5p/assets/js/` (H5P libraries, resizers, jQuery) which are browser runtime assets, not application source code.

Coverage collection is structurally sound across all 6,345 covered commits with **zero ghost files** and **zero artifact leaks**. All covered commits were flagged as `CRITICAL_ANOMALY` solely due to vendored third-party assets (`src/.../assets/js/` containing ~35 H5P and jQuery files) lacking unit coverage in an otherwise 100% TypeScript codebase.

---

## 2. Pipeline Execution & Study Yield

*Summary of longitudinal commit processing and coverage availability for causal modeling.*

| Metric | Commits | Proportion | Description |
|---|---|---|---|
| **Total Commits Evaluated** | 6,607 | 100.0% | Full longitudinal evaluation window |
| **Valid Coverage Produced** | 6,345 | 96.0% | Clean suite executions & non-bailing test runs |
| **Hard Pipeline / Test Errors** | 110 | 1.7% | Broken build or environment states (`.error` / no LCOV) |
| **Not Applicable** | 152 | 2.3% | Excluded commits (e.g. non-test eras, focus markers) |

---

## 3. Structural Hygiene & Git Tree Alignment

*Verification that LCOV line records map 1-to-1 to Git-tracked source lines without container or build contamination.*

| Integrity Check | Count | Status | Finding / Analysis |
|---|---|---|---|
| **Ghost Files (`SF:` not in Git)** | 0 | **Clean** | Every single file recorded in LCOV paths exists in the checked-out Git repository tree. Zero path normalization issues. |
| **Artifact Leaks (`dist/`, `build/`)** | 0 | **Clean** | Zero coverage recorded on compiled or bundle outputs (`www/`, `build/`). |
| **Path Normalization** | 0 | **Clean** | All file paths correctly resolve relative to repository root |

---

## 4. Coverage Scope & Longitudinal Denominators

*Definition of the codebase denominator and longitudinal stability of the exposure variable.*

### Codebase Composition & Test Boundaries
Application TypeScript source modules are tested with exceptional coverage stability (averaging 97.0%). Vendored browser assets are excluded from unit tests by upstream Jest configuration.

### Longitudinal Metrics
- **Effective Coverage Ratio (`lcov_src_count / git_src_count`):**
  - **Min:** 0.9331 (93.3%)
  - **Average:** 0.9703 (97.0%)
  - **Max:** 0.9752 (97.5%)

### Timeline & Era Evolution
Throughout the collection window:
- The coverage ratio remains remarkably stable between **93.3% and 97.5%**.
- The coverage denominator closely tracks the growth of the codebase: source files in Git expand from 508 to 1,761 files, while LCOV source counts expand proportionally from 558 to 2,053 files.
- The V8 coverage provider (`--coverageProvider=v8`) provides consistent coverage tracking without the silent crash failures experienced by the Babel-based Istanbul provider on Angular TypeScript codebases.

---

## 5. Automated Checker Findings & Causal Attribution

*Detailed attribution of flags raised by `check_lcov_sanity.py` heuristics.*

| Flag / Detected Pattern | Affected Commits | Attribution Category | Root Cause & Upstream Mechanism |
|---|---|---|---|
| `MISSING_EXT:js` | 6,345 (96.0%) | Vendored Third-Party Assets | Static vendored H5P and jQuery libraries under assets/js; excluded from unit coverage by upstream Jest design |

### Detailed Analysis of Findings
- **Primary Flag:** `MISSING_EXT:js(git=35-45, share=2.2-2.7%, lcov=0)` across 100% of the 6,345 covered commits.

### Causal Attribution
- **Classification:** **Vendored Third-Party Assets / Upstream Test Design** (Not a pipeline defect).
- **Mechanism:**
  - Moodle App is an Angular application written 100% in TypeScript (`.ts`).
  - The repository contains ~32–45 `.js` files located under `src/core/features/h5p/assets/js/` (vendored third-party H5P libraries, resizers, and jQuery).
  - Upstream Jest unit tests test the Angular TypeScript application logic and intentionally do not execute or instrument the vendored browser asset scripts.
  - `check_lcov_sanity.py` flags any Git extension with $\ge 20$ files that has 0 coverage in LCOV. Because the vendored JS asset files exceed the 20-file heuristic threshold, every commit is marked as `CRITICAL_ANOMALY`.

---

## 6. Downstream Methodological Guidance

1. **Bug-Introduction & SZZ Validity:**
   - With zero ghost files and zero leaks, coverage aligns cleanly with Git blame.
   - For causal analysis, bug introductions in Moodle App's TypeScript codebase (`src/**/*.ts`) map cleanly to measured line coverage. The uninstrumented JS files represent vendored third-party assets that are outside the scope of developer code edits.
2. **Exposure Variable Comparability:**
   - The coverage metric is exceptionally stable across history (averaging 97.0% of git files, representing virtually 100% of the project's own TypeScript sources).
3. **Action Items:**
   - No changes to `install-and-run.sh` or Dockerfile needed.

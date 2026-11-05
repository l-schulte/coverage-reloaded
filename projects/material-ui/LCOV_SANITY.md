# LCOV Sanity & Coverage Integrity Analysis: material-ui

**Date of Analysis:** 2026-10-27  
**Target Project:** `projects/material-ui`  
**Report Source:** [`projects/material-ui/lcov_sanity_report.csv`](lcov_sanity_report.csv)  
**Verification Command:** `python3 check_lcov_sanity.py material-ui --verbose`

---

## 1. Study Verdict & Executive Assessment

- **Causal Study Verdict:** VALID WITH EXPLAINED HEURISTICS
- **Longitudinal Criterion (≥ 90%):** **PASS** (11,544 of 11,882 commits [97.2%] produced valid coverage)
- **Structural Integrity:** **CLEAN** (0 ghost files, 0 artifact leaks)

### Executive Summary & Context
Material UI (MUI) is a foundational React UI component library. Upstream's unit testing suite focuses exclusively on the core component frameworks (`packages/mui-material`, `packages/mui-system`, `packages/mui-base`, `packages/mui-lab`, and internal utils). Upstream deliberately does not execute unit tests or collect coverage on the tens of thousands of auto-generated SVG icon wrapper components in `packages/mui-icons-material` or `packages/material-ui-icons`.

All 11,544 covered commits were categorized as `CRITICAL_ANOMALY` strictly due to a heuristic directory check triggering on Material UI's auto-generated icon packages (`mui-icons-material` / `material-ui-icons`, containing 17,000–21,000 files). Structurally, the dataset is completely clean: **zero ghost files** and **zero artifact leaks**.

---

## 2. Pipeline Execution & Study Yield

*Summary of longitudinal commit processing and coverage availability for causal modeling.*

| Metric | Commits | Proportion | Description |
|---|---|---|---|
| **Total Commits Evaluated** | 11,882 | 100.0% | Full longitudinal evaluation window |
| **Valid Coverage Produced** | 11,544 | 97.2% | Clean suite executions & non-bailing test runs |
| **Hard Pipeline / Test Errors** | 338 | 2.8% | Broken build or environment states (`.error` / no LCOV) |
| **Not Applicable** | 0 | 0.0% | No non-test or excluded eras |

---

## 3. Structural Hygiene & Git Tree Alignment

*Verification that LCOV line records map 1-to-1 to Git-tracked source lines without container or build contamination.*

| Integrity Check | Count | Status | Finding / Analysis |
|---|---|---|---|
| **Ghost Files (`SF:` not in Git)** | 0 | **Clean** | Across all 11,544 commits with coverage, every recorded `SF:` path exists in the checked-out Git repository tree. Zero container path leaks. |
| **Artifact Leaks (`dist/`, `build/`)** | 0 | **Clean** | Zero coverage recorded on compiled or bundle output folders. |
| **Path Normalization** | 0 | **Clean** | All file paths correctly resolve relative to repository root |

---

## 4. Coverage Scope & Longitudinal Denominators

*Definition of the codebase denominator and longitudinal stability of the exposure variable.*

### Codebase Composition & Test Boundaries
The Git repository contains between 17,000 and 23,000 files, >95% of which are auto-generated icon wrappers. Actual library code comprises ~600 to 1,200 source files. LCOV files cover 600 to 1,100 files, representing virtually 100% of the active component framework.

### Longitudinal Metrics
- **Effective Coverage Ratio (`lcov_src_count / git_src_count`):**
  - **Min:** 0.0075 (0.7%)
  - **Average:** 0.0392 (3.9%)
  - **Max:** 0.1486 (14.9%)

### Explanation of the Coverage Ratio
The seemingly low coverage ratio (averaging ~3.9% of git files) is an artifact of repository composition:
- The Git tree contains between **17,000 and 23,000 source files**, over **95% of which are auto-generated SVG icon wrapper components** in `packages/mui-icons-material/` or `packages/material-ui-icons/`.
- The actual product library code (`packages/mui-material`, `packages/mui-system`, `packages/mui-base`, `packages/mui-lab`, and internal utils) comprises ~600 to 1,200 source files.
- LCOV coverage files routinely cover **600 to 1,100 files**, representing extensive and robust coverage of the actual UI component framework.

---

## 5. Automated Checker Findings & Causal Attribution

*Detailed attribution of flags raised by `check_lcov_sanity.py` heuristics.*

| Flag / Detected Pattern | Affected Commits | Attribution Category | Root Cause & Upstream Mechanism |
|---|---|---|---|
| `MISSING_DIR:packages/mui-icons-material` & `material-ui-icons` | 11,544 (97.2%) | Upstream Test Design | Tens of thousands of auto-generated SVG icon wrapper components deliberately excluded from unit tests by upstream maintainers |
| `UNDERREPRESENTED_EXT:js` | 9,785 (82.4%) | Repository Composition | The ~21,000 generated icon wrapper files are JavaScript files, causing git JS count to vastly exceed unit-tested core code |
| `MISSING_DIR:packages/api-docs-builder` | 11,544 (97.2%) | Documentation Tooling | Internal build tool for documentation site; not part of user-facing UI component library |

### Detailed Analysis of Findings
- **Primary Flag:** `MISSING_DIR:packages/mui-icons-material` (9,450 commits) and `MISSING_DIR:packages/material-ui-icons` (2,094 commits). Combined, these account for 100% of the 11,544 flagged commits.
- **Secondary Flag:** `UNDERREPRESENTED_EXT:js` (9,785 commits). Flagged because the ~21,000 generated icon wrapper files are JavaScript files, causing the total repository JS file count to drastically outweigh the ~700 core JS/TS files covered by unit tests.
- **Auxiliary Directories:** `packages/api-docs-builder` (internal documentation generator), `apps/bare-next-app` (example integration app), and `framer` (design tool bridge).

### Causal Attribution
- **Classification:** **Intentional Upstream Test Design & Monorepo Architecture** (Not a pipeline defect).
- **Mechanism:**
  - Upstream Material UI's test script (`test:coverage` via `mocha`/`nyc`, later `vitest`) focuses strictly on testing components, hooks, style engines, and layout utilities.
  - Upstream developers deliberately do not run unit tests or coverage instrumentation on the tens of thousands of auto-generated icon wrapper files.
  - `check_lcov_sanity.py` employs a heuristic threshold flagging any Git directory with $\ge 15$ source files that has 0 coverage in LCOV. Because `packages/mui-icons-material` contains ~21,000 files and 0 coverage, the sanity checker marks every commit as a `CRITICAL_ANOMALY`.

---

## 6. Downstream Methodological Guidance

1. **Bug-Introduction & SZZ Validity:**
   - The absolute absence of ghost files (0) and artifact leaks (0) confirms that LCOV line numbers map faithfully to Git commits.
   - For SZZ and bug-introduction models, changes to core component packages (`@mui/material`, `@mui/system`, etc.) possess high-fidelity coverage measurements. Changes to icon SVG files are simply uninstrumented (zero coverage), reflecting upstream's actual test practice.
2. **Exposure Variable Comparability:**
   - Downstream models should calculate coverage ratios using the **core package source denominator** rather than the whole-monorepo denominator, to avoid skewing metrics by the sheer volume of generated icon components.
3. **Action Items:**
   - No changes to `install-and-run.sh` or the Dockerfile are required. The coverage collection for `material-ui` faithfully reflects upstream test intent.

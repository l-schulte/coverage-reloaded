# Temporary Handoff Notes: island.is Onboarding
> **NOTE: TO BE DELETED ONCE MAIN OVERVIEW IS WRITTEN**

---

## 1. Project Context & Objectives
* **Repository**: `island-is/island.is` (`island`)
* **Scale**: ~11,000 commits over 5.5 years (2020–2026), ~500 monorepo packages, 129 testable projects.
* **Benchmark Target Commit**: `7fa8be6b92c0d5a956216b058bce11a914a6854c` (Dec 2025, Yarn Berry / Yarn 4.6.0, Nx monorepo, Jest runner).
* **Core Requirement**: Collect valid longitudinal line coverage across all testable projects within the 90-minute container limit with zero test bailing (`--no-bail` adherence).

---

## 2. Core Monorepo Challenges & Solutions

### A. The RootDir / Preset Coverage Path Mismatch
* **Problem**: Root `jest.preset.js` specifies `collectCoverageFrom: ['src/**/*.{js,jsx,ts,tsx}']`. Because individual project configs set `rootDir: '../../..'`, Jest looks for `/src` at the repo root. Since no `/src` exists at the root, Jest originally matched 0 files and emitted empty LCOVs across all projects.
* **Solution**: Passed `--collectCoverageFrom=**/*.{ts,tsx}` via CLI, enabling Jest to find source files inside each project's directory.

### B. Dynamic Project Discovery & Classification
In `install-and-run.sh`, test projects are discovered dynamically (supporting both modern Nx and legacy `workspace.json`) and partitioned into three distinct suites:
1. **Targeted (`unit-targeted`)**: Outlier packages requiring specialized test flags (`skilavottord-web`, `shared-babel`).
2. **Light (`unit-light`)**: Standard projects with `< 100` spec files (126 projects, run with `nx run-many --parallel=8 --maxWorkers=1`).
3. **Heavy (`unit-heavy`)**: Large packages with `>= 100` spec files (`judicial-system-backend` with 515 specs, run with `--parallel=2 --maxWorkers=6` to prevent timeouts).

### C. Isolating Outlier Projects (`unit-targeted`)
Instead of applying broad global exclusion flags that could cause collateral exclusions in healthy packages:
* **`skilavottord-web`**: A Next.js app using `ts-jest` that only tests `utils/encodeUtils.ts`. Its Jest config was never set up with Next.js Babel presets to compile un-tested frontend UI components (`screens/`, `components/`, `pages/`). Runs isolated with `--collectCoverageFrom=apps/skilavottord/web/utils/**/*.{ts,tsx}`.
* **`shared-babel`**: Contains AST parser test fixtures with intentional duplicate exports. Runs isolated with `--collectCoverageFrom=!libs/shared/babel/src/exportFinder/test/fixture/**`.

### D. Environment & Runtime Stubs
* **Global Fetch Mock**: Generated at `/coverage_reloaded/repo/jest-setup-fetch.ts` to satisfy NextAuth and API client suites running under JSDOM.
* **Coverage Directory Normalization**: Node script normalizes `coverageDirectory` in each project's `jest.config.*` to ensure each project writes to `/coverage_reloaded/repo/coverage/<pkg-dir>`.

---

## 3. File Inventory

| File | Purpose / Role |
|---|---|
| `projects/island/install-and-run.sh` | Main container runner script (documented with inline comments). |
| `projects/island/Dockerfile` | Base container definition with `LABEL dind.project="true"`. |
| `projects/island/logs/` | Execution logs and error traces from benchmark and batch runs. |

---

## 4. Next Steps for the Next Chat

1. **Verify the benchmark run**: Check the latest log for `7fa8be6b92c0d5a956216b058bce11a914a6854c` to ensure all 129 projects (including `unit-targeted`) produced valid non-empty LCOVs.
2. **Review Batch Run Results**: Analyze recent logs in `projects/island/logs/` across older commits to identify any historical era boundaries (e.g. Yarn 1 transitions, older Nx 11 `workspace.json` schemas) that require branching logic.

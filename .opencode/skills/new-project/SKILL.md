---
name: new-project
description: Preliminary feasibility assessment for a new project. Analyzes command_changes.csv, classifies test scripts, checks for coverage gates, and produces a prototype Dockerfile + install-and-run.sh. Iterative protocol with user checkpoints between each phase.
license: MIT
metadata:
  audience: developers
  workflow: project-onboarding
---

## What I do

Assess whether a new project can be onboarded into the coverage_reloaded pipeline and produce a working prototype. I analyze `command_changes.csv` to understand the project's test infrastructure, check for coverage gates that would invalidate the exposure variable, and create initial `Dockerfile` + `install-and-run.sh` files. I work in short, bounded phases with explicit stop points where I present findings and wait for user feedback before proceeding.

## Context

- The pipeline collects longitudinal line-based coverage across full commit history. Coverage is the exposure variable in a causal study — measurement bias threatens validity.
- **Inclusion criterion:** ≥ 90% of a project's last-5-years commits must produce valid coverage.
- **Coverage thresholds are confounds**, not features. If the project enforces them, we cannot use it. See AGENTS.md §3.
- E2e tests are **excluded** — only unit and integration tests.
- `command_changes.csv` shows the full history of `package.json` script changes: one row per unique `(script_name, script_definition)` pair with earliest commit. Removal rows have blank `script_definition`.
- CI configs (`.github/workflows/`, `.circleci/`, `.gitlab-ci.yml`, `Jenkinsfile`, `Makefile`, `Dockerfile*`, `docker-compose*.yml`, `.travis.yml`) in the repo often reveal exact test commands, env vars, system deps, and coverage flags the project actually uses. **Always check these.**

## Iterative Protocol

Run phases sequentially. Stop after each phase. Present your full findings before moving on. Wait for the user's input before proceeding.

### Phase 1 — Script Inventory & Classification

Bounded scope: read `command_changes.csv` and related files, classify everything, do not write any code yet.

1. **Read `projects/<name>/command_changes.csv`**. Parse all rows.
2. **Group scripts by type:**
   - **Unit tests:** scripts whose names or definitions reference `test:unit`, `test:ci`, `jest`, `vitest`, `mocha`, `ava`, `tap`, `karma`, or similar unit-level runners.
   - **Integration tests:** scripts referencing `test:integration`, `test:e2e` (if they run server-side against a real backend), `test:api`, or similar.
   - **E2e tests:** scripts referencing `test:e2e`, `test:cypress`, `test:playwright`, `test:selenium`, `cypress run`, `playwright test`, or browser-based runners. **Exclude these** — report them but do not plan coverage for them.
   - **Build/prep scripts:** `build`, `prepare`, `prebuild`, `postbuild`, `compile`, `tsc`, `rollup`, `webpack`, etc. Identify which are required before tests can run.
   - **Other:** anything that doesn't fit above — lint, format, deploy, etc.
3. **Identify test runners** and how coverage can theoretically be collected from each:
   - `jest` → `jest --coverage` or wrap with `c8`/`nyc`
   - `vitest` → `vitest --coverage` (needs `@vitest/coverage-v8` or `@vitest/coverage-istanbul`)
   - `mocha` → wrap with `nyc`
   - `ava` → wrap with `c8`
   - `karma` → `karma-coverage` plugin or wrap with `nyc`
   - Other → assess case by case
4. **Scan repo for CI configs and documentation** within the relevant timeframe (2020–2025). These are gold mines for understanding how the project actually runs its tests:
   ```bash
   # Find CI config files that existed in the repo's history
   git -C projects/<name>/repo log --after=2020-01-01 --before=2026-01-01 \
     --name-only --pretty=format: -- \
     '.github/workflows/*.yml' '.circleci/*' '.gitlab-ci.yml' \
     'Jenkinsfile' 'Makefile' 'Dockerfile*' 'docker-compose*.yml' \
     '.travis.yml' '.appveyor.yml' | sort -u | head -50
   ```
   For each found file, read its content at a representative commit to extract:
   - Exact test commands used in CI
   - Environment variables set (especially coverage-related ones)
   - System-level dependencies (apt packages, services, databases)
   - Node version and package manager version used
   - Coverage tool configuration (if any)
5. **Check for workspace/monorepo structure** — does `package.json` have `workspaces`? Are there multiple packages with their own test scripts?

**Checkpoint 1:** Present a full summary:

```
# Phase 1 — Script Inventory: <project>

## Script Groups
| Type | Script Name | Definition | Commits Affected |
|------|-------------|------------|-------------------|
| Unit | test:unit | jest --runInBand | 2020-01 → 2025-12 |
| ... | ... | ... | ... |

## Build/Prep Required Before Tests
| Script | Definition | Why |
|--------|------------|-----|
| build | tsc | compiles TS before tests can import |

## E2e Tests (EXCLUDED)
| Script | Definition | Runner |
|--------|------------|--------|
| test:e2e | cypress run | Cypress |

## Test Runners & Coverage Approach
| Runner | How to Collect Coverage |
|--------|------------------------|
| jest | jest --coverage or wrap with c8 |

## CI Config Findings
| File | Commit | Key Findings |
|------|--------|--------------|
| .github/workflows/ci.yml | abc123 | runs `npm test`, node 18, ubuntu-latest |

## Monorepo? Yes/No
## Packages with tests: [list]
```

Ask: *"Does this match what you expect? Any scripts I misclassified? Proceed to coverage gate check?"*

### Phase 2 — Coverage Gate Detection

Bounded scope: only check for coverage thresholds. Do not read test logic or trace imports.

1. **Inspect `command_changes.csv`** for scripts containing coverage gate indicators:
   - `--check-coverage` in any script definition
   - `--lines`, `--branches`, `--functions` thresholds
   - `coverageThreshold` in jest config references
2. **If a recent commit has coverage config files**, inspect them:
   ```bash
   git -C projects/<name>/repo show <hash>:.c8rc.json 2>/dev/null
   git -C projects/<name>/repo show <hash>:.nycrc 2>/dev/null
   git -C projects/<name>/repo show <hash>:jest.config.js 2>/dev/null | grep -i threshold
   git -C projects/<name>/repo show <hash>:jest.config.ts 2>/dev/null | grep -i threshold
   ```
3. **Check `package.json` at a recent commit** for `coverageThreshold` in jest/vitest config.
4. **Check for custom test wrappers** (`bin/test.js`, `scripts/test.sh`) that enforce coverage floors.

**If coverage gates found:** Report them clearly. **Do NOT proceed to Phase 3.** The project is not usable for the causal study — the gates confound the exposure variable.

**Checkpoint 2:** Present findings:

```
# Phase 2 — Coverage Gates: <project>

## Result: CLEAN / GATES FOUND

### If CLEAN:
No coverage thresholds detected. Project is a candidate for onboarding. Proceed to prototype?

### If GATES FOUND:
| Gate | Location | Details |
|------|----------|---------|
| --check-coverage | package.json test:coverage | exits non-zero if below 80% |

⚠️ This project has coverage gates that confound the exposure variable.
We cannot use it. Recommendation: DISCARD.
```

Ask: *"Proceed to prototype, or discard the project?"*

### Phase 3 — Prototype Implementation

Bounded scope: create `Dockerfile` and `install-and-run.sh` based on findings from Phase 1. These are prototypes — they will need iteration.

1. **Write `projects/<name>/Dockerfile`** following the base image pattern:
   ```dockerfile
   FROM core_node${NODE_VERSION}_base
   # Add system dependencies identified in Phase 1 (CI configs, build failures)
   # Example: RUN apt-get update && apt-get install -y <packages>
   COPY ./repo /coverage_reloaded/repo
   COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
   ```
   - Use system deps found in CI configs or Dockerfiles from the repo's history.
   - Default to `core_node${NODE_VERSION}_base` (set by the pipeline).
   - Only add what's necessary — keep it minimal.

2. **Write `projects/<name>/install-and-run.sh`** following AGENTS.md §6 constraints:
   - `set -e` at top
   - Branch on `$IS_NPM_MAIN_PM` / `$IS_YARN_MAIN_PM` / `$IS_PNPM_MAIN_PM`
   - Use `git show` or inspect the checked-out commit to detect what to run — do not hardcode
   - Pin registries: project deps → `$WAYPACK_NPM_REGISTRY`, our tooling (c8/nyc) → `$VERDACCIO_REGISTRY`
   - Wrap each suite with `suite_start` / `suite_end`
   - `set +e` only around test commands, capture exit code, restore `set -e`
   - Call `bash ../find-and-move-lcov.sh` after each suite
   - `--maxWorkers=1` / `--runInBand` for jest/vitest
   - No `--bail`, `|| true`, `2>&1 | tail`, or error suppression
   - No comments unless user asks for them

3. **Write both files to disk** at `projects/<name>/Dockerfile` and `projects/<name>/install-and-run.sh`.

**Checkpoint 3:** Present the files and summary:

```
# Phase 3 — Prototype: <project>

## Files Written
- projects/<name>/Dockerfile
- projects/<name>/install-and-run.sh

## What the prototype covers
- [list of suites identified in Phase 1]
- [list of build steps included]
- [list of system deps added]

## What needs manual testing
- [ ] Run: python main.py --project <name> --mode single-commit --commit-hash <hash>
- [ ] Verify lcov.info is produced
- [ ] Check for missing system deps (gyp errors)
- [ ] Verify WayPack resolution for this project's packages

## Known gaps
- [any assumptions made that need verification]
```

Ask: *"Prototype written. Ready to test with a single commit, or do you want to adjust anything first?"*

## Off-Limits — Strictly Enforced

- **No `|| true`, `|| { echo ...; exit 1; }`, `2>&1 | tail`, or error suppression** in any generated code.
- **No modifying shared scripts** (`execute.sh`, `find-and-move-lcov.sh`, `logging.sh`).
- **No running containers** — the prototype is written to disk and tested by the user.
- **No coverage gates** — if Phase 2 finds them, stop and report. Do not write prototypes for projects with gates.
- **No bail flags** — ever. See AGENTS.md §2.
- **No comments** in generated code unless explicitly asked.

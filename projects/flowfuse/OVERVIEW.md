# flowfuse

**Repository:** https://github.com/FlowFuse/flowfuse
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `flowfuse`).
- **Node strategy:** `node_version_delay_months = 24`, `min_node_version = 14`.
- **Runners:** `mocha`, `vitest`.
- **Eras:** `test:unit` runs `mocha` specs and later delegates to `test:unit:forge`
  and `test:unit:frontend`. `test:unit:forge` runs `mocha`; `test:unit:frontend`
  runs `vitest`; `test:system` runs system tests with `mocha`. Only root scripts
  exist.

## Coverage collection

- **Suites collected:** `test:unit` (and its delegated forge/frontend suites),
  `test:system`.
- **Suites excluded:** end-to-end and documentation tests.
- **Focus markers:** commits whose collected suites contain a committed `.only`
  are marked not-applicable rather than recording subset coverage (see
  [`STUDY_DECISIONS.md`](../../STUDY_DECISIONS.md) §2).
- **Coverage tool / config:** `nyc`. From the nyc era onward the project's own
  `nyc` + `.nycrc.json` (`include: forge/**`) drives collection. The 641
  pre-nyc-era commits (2021-07-29 to 2022-03-21) are instrumented with an injected
  `nyc@15` using `--all --include 'forge/**' --include 'ee/**'`, reproducing the
  project's own file set so the exposure variable is produced by a single tool and
  file set across the whole history.
- **LCOV production:** `nyc` with an `lcov` reporter.

## Checklist

- [x] 100 done (92/100)
- [x] failed tests doublechecked (few and genuine)
- [x] complete run (nyc-only re-run of the 641 pre-nyc commits completed)
- [x] complete test failure check
- [x] complete JEV test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-10-09 13:26).

| Metric | Value |
|---|---|
| Commits processed | 15802 |
| Without test failures | 13157 |
| With test failures | 1540 |
| Not applicable | 319 |
| Hard errors | 786 |
| Coverage produced | 94.9% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `Cannot read properties of undefined (reading 'map')` — HTTP 500 on `GET /api/v1/projects/:id`, thousands per run (21 runs) | acceptable | none; `nyc` still emits `lcov` (500 vs expected 200), so coverage is valid | None. Genuine repository regression. |
| `Module not found: Error: Can't resolve '@/pages/Account/index.vue'` — Webpack build failure in `frontend/src/routes/index.js` | acceptable | hard error; `npm run build` aborts, preventing backend test execution across 39 commits | None. Genuine repository regression on Linux (fixed upstream in `da1e8d159`). |
| `Error: [vite-node] Failed to load @/...` — `test/unit/frontend/` specs (`users`, `team`, `billing`, `nav-item`) | acceptable | none; valid partial frontend coverage emitted, backend coverage valid (exit 1) across 345 runs | None. Genuine repository regression (fixed upstream in `3ca495c698`). |
| `Cannot find module './stack.js'` — `forge/routes/api/index.js:14` requires a file added only by the next commit | reevaluated_acceptable | none; valid partial coverage, unit exit 1 (8 failing) | None. Genuine upstream broken commit `90460285` (fixed by `7e64532f5`). |
| `Cannot find module './DeviceGroup'` — `forge/db/views/index.js:18` requires view file added only in subsequent commit `ef462b266` (5 runs) | reevaluated_acceptable | none; valid partial coverage, unit exit 1 | None. Genuine upstream uncommitted file in commit `a825fbee6a` (fixed by `ef462b266`). |
| `Cannot find module '../../services/product.js'` — `forge/product/index.js` requires service file added in subsequent commit (1 run) | reevaluated_acceptable | none; valid partial coverage, unit exit 1 | None. Genuine upstream uncommitted file in commit `6a4dfd22bc`. |
| `Invalid module version: v1` / `v2` — `ERROR` from `ProjectTemplate.validateSettings` | reevaluated_acceptable | none; app log during passing negative tests | None. Intentional validation logging (keyword false positive), not a test failure. |

Root cause of the `map` failure: commit `4e350d4b` ("hide template settings hidden
env values") added an unguarded
`project.template.settings.env = project.template.settings.env.map(...)` in
`forge/routes/api/project.js:94`. The preceding commit `6c27303b` (same day, about
2.5 hours earlier) lacks this line and throws zero such errors. The project's own
test fixtures create templates with `settings: {}` (no `env` key), for example
`test/unit/forge/ee/setup.js` (`template1`),
`test/unit/forge/db/models/Project_spec.js`, and
`test/unit/forge/ee/routes/api/pipeline_spec.js`. The `pool-shim.js` SQLite fix is
inert for this failure (6834 errors pre-shim vs 6840 post-shim). Do not relabel as
environment.

Root cause of the `Account/index.vue` failure: commit `952a7ee3` ("Big rework of ui
front end (#45)") introduced `import Account from "@/pages/Account/index.vue"` in
`frontend/src/routes/index.js:3`, whereas the committed directory on disk is
`frontend/src/pages/account/` (lowercase `a`). On macOS (default APFS/HFS+ case-insensitive
filesystems), the path resolves without error. On Linux (case-sensitive ext4), Webpack
fails during `npm run build`. Upstream fixed the defect in commit `da1e8d159` ("Fix case
of route import"). Spans 39 commits.

Root cause of the Vitest `@` alias failure: commit `c2611a97` ("Add passing API test
dependent on @/api/client", May 2022) placed `alias: { '@': ... }` at the root level
of `defineConfig` in `config/vitest.config.ts`. In Vite/Vitest, aliases must be
nested under `resolve: { alias: { ... } }`. Consequently, Vitest failed to resolve
`@/` imports in `users.spec.js`, `team.spec.js`, `billing.spec.js`, and `nav-item.spec.js`.
Upstream resolved this in commit `3ca495c698` ("Update config for @ alias", November
2022). Spans 345 runs.

Root cause of the `DeviceGroup` failure: commit `a825fbee6a` ("Add App Device Groups
API", Dec 2023) registered `'DeviceGroup'` in `modelTypes` inside `forge/db/views/index.js`,
but author Stephen McLaughlin forgot to commit `forge/db/views/DeviceGroup.js`. Upstream
added the missing view file the following day in commit `ef462b266dac` ("Add DeviceGroup db
view"). Spans 5 runs.

Root cause of the `services/product.js` failure: commit `6a4dfd22bc` introduced an import of
`../../services/product.js` in `forge/product/index.js` before the service module was
committed upstream. Spans 1 run.

## Environment / setup fixes

- **SQLite `:memory:` connection race.** Symptom: a cascade of
  `no such table: MetaVersions` / `duplicate column name: editorAffinity` failures
  yielding 0% coverage or a crash across ~34 commits (April 2025). Root cause:
  SQLite `:memory:` is per-connection, so pooled connections see different empty
  databases; `init()` creates `MetaVersion` on one connection while
  `checkPendingMigrations` queries it on another, re-applying migrations. Fix:
  `projects/flowfuse/pool-shim.js`, injected via
  `NODE_OPTIONS="--require /coverage_reloaded/pool-shim.js"`. It force-injects
  `pool: { max: 1, min: 1 }` into any Sequelize constructor configured with
  `storage: ':memory:'`, giving each app a single isolated in-memory connection.
  Whitelisted in `.dockerignore` (`!pool-shim.js`) and copied by the Dockerfile.
- **`sqlite3` native module (build from source).** Symptom: two native-module
  failure families in the forge backend, both crashing `forge_unit`/`system`
  (exit 100/255/12): `Could not locate the bindings file` (prebuilt `sqlite3`
  `.node` addon absent for the installed Node ABI, Node 20 era, 6 commits) and
  `GLIBC_2.33 not found` (prebuilt addon built against a newer glibc than the
  bullseye base image, glibc 2.31, Node 16 era, 3 commits). Root cause:
  `npm rebuild sqlite3` re-ran `node-pre-gyp` and re-downloaded an incompatible
  prebuilt binary. Fix: when `require('sqlite3')` fails to load, run
  `npm_config_build_from_source=true npm rebuild sqlite3`. The check is
  conditional, so already-working runs are not recompiled. Status: fix applied
  and verified on the 3 GLIBC and 6 bindings commits; labeled `problematic` in
  `failure_labels_project.csv`.
- **Git submodules for `file:sub_modules/` dependencies.** Symptom: `npm install`
  failing with `npm ERR! code ENOLOCAL: Could not install from "sub_modules/flowforge-driver-localfs"`
  across 174 historical commits (late 2021 / early 2022). Root cause: `package.json`
  declared local dependencies pointing to Git submodules tracked in `.gitmodules`,
  but `execute.sh` does not run submodule updates on checkout. Fix: conditionally
  execute `git submodule update --init` before `npm install` in `install-and-run.sh`
  when `.gitmodules` exists and `package.json` declares `file:sub_modules/` dependencies.
- **Cypress binary download bypass.** Symptom: `npm install` failing with
  `npm error [FAILED] Error: getaddrinfo EAI_AGAIN download.cypress.io` across 111 commits.
  Root cause: Cypress postinstall attempts to download desktop binaries from an
  external domain blocked in the sandbox. Fix: `export CYPRESS_INSTALL_BINARY=0` in
  `install-and-run.sh`. (E2E Cypress suite is excluded from coverage collection).
- **Version-matched Vitest coverage provider.** Symptom: `test:unit:frontend` crashing
  with `Cannot find module 'vitest/coverage'` and failing hard with no `lcov.info`
  across ~295 commits. Root cause: `install-and-run.sh` installed an unversioned
  `@vitest/coverage-v8`, which was incompatible with Vitest `< 0.32` (which required
  `@vitest/coverage-c8` with an exact version match). Fix: detect installed Vitest
  version and conditionally install `@vitest/coverage-c8@$VERSION` (< 0.32) or
  `@vitest/coverage-v8@$VERSION` (≥ 0.32) only when no coverage provider is present.

## Known gaps

- **Committed focus markers (`.only`).** 81 collected commits contain a
  `describe.only`/`it.only` in a collected suite (`test/unit/` or `test/system/`;
  40 distinct spec files, 2022-09 → 2025-12). Mocha/vitest would run only the
  marked subset and emit a valid-looking but unrepresentative `lcov`, so these
  commits are marked not-applicable by `na_if_focus_marker` (see
  [`STUDY_DECISIONS.md`](../../STUDY_DECISIONS.md) §2). The 79 that previously
  recorded subset coverage were re-run; the 2 that were hard errors were
  reclassified.

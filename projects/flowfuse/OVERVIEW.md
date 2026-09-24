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
- **Coverage tool / config:** `nyc`.
- **LCOV production:** `nyc` with an `lcov` reporter.

## Checklist

- [x] 100 done (92/100)
- [x] failed tests doublechecked (few and genuine)
- [x] complete run
- [x] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-24 10:35).

| Metric | Value |
|---|---|
| Commits processed | 15802 |
| Without test failures | 13215 |
| With test failures | 1550 |
| Not applicable | 238 |
| Hard errors | 799 |
| Coverage produced | 94.9% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `Cannot read properties of undefined (reading 'map')` — HTTP 500 on `GET /api/v1/projects/:id`, thousands per run (21 runs) | acceptable | none; `nyc` still emits `lcov` (500 vs expected 200), so coverage is valid | None. Genuine repository regression. |
| `Module not found: Error: Can't resolve '@/pages/Account/index.vue'` — Webpack build failure in `frontend/src/routes/index.js` | acceptable | hard error; `npm run build` aborts, preventing backend test execution across 39 commits | None. Genuine repository regression on Linux (fixed upstream in `da1e8d159`). |
| `Error: [vite-node] Failed to load @/...` — `test/unit/frontend/` specs (`users`, `team`, `billing`, `nav-item`) | acceptable | none; valid partial frontend coverage emitted, backend coverage valid (exit 1) across 345 runs | None. Genuine repository regression (fixed upstream in `3ca495c698`). |
| `Cannot find module './stack.js'` — `forge/routes/api/index.js:14` requires a file added only by the next commit | reevaluated_acceptable | none; valid partial coverage, unit exit 1 (8 failing) | None. Genuine upstream broken commit `90460285` (fixed by `7e64532f5`). |
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

None.

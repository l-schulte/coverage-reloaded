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
- [wip] complete run
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-09 07:13).

| Metric | Value |
|---|---|
| Commits processed | 947 |
| Without test failures | 682 |
| With test failures | 193 |
| Not applicable | 14 |
| Hard errors | 58 |
| Coverage produced | 93.8% |
| Commits not yet processed | 14855 |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `Cannot read properties of undefined (reading 'map')` — HTTP 500 on `GET /api/v1/projects/:id`, thousands per run | acceptable | none; `nyc` still emits `lcov` (500 vs expected 200), so coverage is valid | None. Genuine repository regression. |

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
  conditional, so already-working runs are not recompiled. Status: `fix_applied`
  and verified on the 3 GLIBC and 6 bindings commits; labeled `fix_applied` in
  `failure_labels_project.csv`.

## Known gaps

None documented.

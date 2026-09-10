# opencrvs-core

**Repository:** https://github.com/opencrvs/opencrvs-core
**Status:** active

> **Preliminary.** The first prototype only. `install-and-run.sh`, `Dockerfile`,
> and `patch-coverage.js` are written and dry-run-tested on git snapshots, but no
> single-commit container run has been performed yet. Era/runner edge cases are
> expected to surface during validation.

## Test infrastructure

- **Package manager:** yarn (2020-01 → ~2025-05) → pnpm (~2025-05 → 2025-12); lerna
  monorepo with pnpm workspaces (see [`config.json`](../../config.json) →
  `opencrvs-core`). Root `test` = `lerna run test --stream`.
- **Node strategy:** default.
- **Runners:**
  - `jest` — backend packages (`auth`, `commons`, `gateway`, `notification`,
    `search`, `user-mgnt`, `webhooks`, `workflow`, `config`) for the whole
    timeframe.
  - `vitest` — `client` (from ~2022-08, replacing craco/jest), `events` (from 2024).
  - `craco test` — `client` early era (2020–2022), wraps jest.
- **Eras:** `packages/e2e` uses Cypress (excluded); `test-storybook` in `client` is
  excluded. Neither is part of the root `test` dispatch.

## Coverage collection

- **Suites collected:** the root `test` script (`lerna run test`).
- **Suites excluded:** Cypress/Playwright e2e and `test-storybook`; their scripts
  are neutralised to noops.
- **Coverage tool / config:** `patch-coverage.js` walks every `package.json`
  outside `node_modules`/`.git`/`dist`/`build`/`lib` and appends runner coverage
  flags:
  - `jest` → `--coverage --coverageReporters=lcov --maxWorkers=2` (strips
    `--no-coverage`)
  - `vitest` → `--coverage --reporters=lcov --maxWorkers=2`
  - `craco test` → `--coverage --coverageReporters=lcov --maxWorkers=2`
  - root `test`: `lerna run test` → `--no-bail --concurrency=1`
- **LCOV production:** `lerna run build` runs first because tests import workspace
  packages via `dist/`; then `find-and-move-lcov.sh "test" "true"`.

## Checklist

- [ ] 100 done (work in progress — first prototype, not yet validated in a container)
- [ ] failed tests doublechecked
- [ ] complete run
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 10:07).

| Metric | Value |
|---|---|
| Commits processed | 100 |
| Without test failures | 4 |
| With test failures | 86 |
| Not applicable | 0 |
| Hard errors | 10 |
| Coverage produced | 90.0% |
| Commits not yet processed | 13300 |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| Storybook build failure (commit `42315429`, 2023-04, Node 16): `lerna run build-storybook` fails because the `build-storybook` binary is missing from `node_modules` | acceptable | hard failure, no coverage produced | None. The project's own Storybook build is broken at this commit; developers would hit this too. |

## Environment / setup fixes

None.

## Known gaps

- **Postinstall hook** (`node development-environment/link-ts6-api.js`): left to
  run; it may fail in the container if it expects specific paths.
- **Older commits (2020):** the `craco test` path is covered but untested; it may
  need iteration.
- **Package-manager transition (~2025-05):** commits around the yarn → pnpm switch
  may have inconsistent lockfiles. The pipeline branches on
  `$IS_PNPM_MAIN_PM` / `$IS_YARN_MAIN_PM` based on which lockfile exists at the
  checked-out commit.
- **Coverage flags missing in some packages:** `gateway` and `client` (latest era)
  lack `--coverage` in their test scripts; the patch script adds it.

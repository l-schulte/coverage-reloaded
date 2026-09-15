# opencrvs-core

**Repository:** https://github.com/opencrvs/opencrvs-core
**Status:** active

## Test infrastructure

- **Package manager:** yarn (workspaces + lerna; runs observed with `yarn@1`),
  see [`config.json`](../../config.json) → `opencrvs-core`.
- **Node strategy:** default.
- **Runners:**
  - `jest` — backend packages (`auth`, `commons`, `gateway`, `notification`,
    `search`, `user-mgnt`, `webhooks`, `workflow`, `config`).
  - `vitest` — `client` (from ~2022-08, replacing craco/jest) and `events`
    (from 2024).
  - `craco test` — `client` early era (2020–2022), wraps jest.
- **Eras:** `packages/e2e` uses Cypress (excluded); `test-storybook` in `client`
  is excluded. Neither is part of the root `test` dispatch.

## Coverage collection

- **Suites collected:** the root `test` script (`lerna run test`).
- **Suites excluded:** Cypress/Playwright e2e and `test-storybook`; their scripts
  are neutralised to noops.
- **Coverage tool / config:** `patch-coverage.js` walks every `package.json`
  outside `node_modules`/`.git`/`dist`/`build`/`lib` and appends runner coverage
  flags. Vitest handling is version-aware:
  - `jest` / `craco test` → `--coverage --coverageReporters=lcov --maxWorkers=2`.
  - `vitest` ≥ 1 (events) → `--coverage --coverage.reporter=lcov
    --maxWorkers=2 --minWorkers=2`; the provider `@vitest/coverage-v8` (pinned to
    the resolved vitest version) is installed out-of-tree after install.
  - `vitest` 0.x (client, login) → `--coverage.enabled=true
    --coverage.reporter=lcov`, with parallelism capped via
    `VITEST_MAX_THREADS=2 VITEST_MIN_THREADS=2`.
  - root `test`: `lerna run test` → `--no-bail --concurrency=1`.
- **LCOV production:** `lerna run build` runs first because tests import workspace
  packages via `dist/`; then `find-and-move-lcov.sh "test" "true"`.
- **Install:** `yarn install --frozen-lockfile --ignore-scripts` (matches the
  project's CI and avoids lockfile rewrites / hoisting drift). `patch-coverage.js`
  runs first and records any required vitest provider in
  `.coverage-providers.json`; the provider is installed after install into
  `node_modules/.coverage-providers/` and symlinked into the consuming package.

## Checklist

- [x] 100 done (100-commit sample reviewed)
- [wip] failed tests doublechecked (requires ≥90% coverage on the 100-commit run; new run in progress)
- [ ] complete run (11643 commits not yet processed)
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-13 14:21).

| Metric | Value |
|---|---|
| Commits processed | 81 |
| Without test failures | 5 |
| With test failures | 67 |
| Not applicable | 0 |
| Hard errors | 9 |
| Coverage produced | 88.9% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Example log | Classification | Coverage impact | Action |
|---|---|---|---|---|
| events `tsc --noEmit` errors in `event.actions.correction-2.test.ts` (`conditionals` property) | `1761137166_2323e82f…`, `1761137580_a3d669b6…` | Developer-facing | Partial (events coverage absent) | None. Developers fixed in `0b2a10fa64` (2025-10-23). |
| events build TS errors at WIP merge commits (`eventId`, `declare.ts`) | `1756553412_052d2446…` | Developer-facing | Hard error | None. Broken intermediate merge. |
| commons build TS7030 (`test.utils.ts`) | `1757671977_6510d552…` | Developer-facing | Hard error | None. |
| gateway build TS6059 (rootDir) / TS2306 (`schema.d.ts`) | `1760530202_39ebc6cf…`, `1738856319_f0a9a84e…` | Developer-facing | Hard error | None. |
| toolkit build TS2749 (`Clause`) | `1737361393_e9381270b…` | Developer-facing | Hard error | None. |
| integration build TS2300 duplicate `AbortController` (nested typescript) | `1637766430…`, `1638254558…`, `1638962287…` | Environment/setup | Hard error | Dependency TS-version conflict; candidate for version pin. |
| gateway build TS7016 missing `@opencrvs/commons` declaration | `1639765873_877100faa…` | Environment/setup | Hard error | Build-ordering / missing types; candidate for fix. |
| search `FAIL search.test.ts` (No Docker client strategy / ES ECONNREFUSED) | `1761137166_2323e82f…` | Environment (one-off flake) | Partial | None; search passes in adjacent commits. |
| login `test:compilation` TS2769 in `vite.config.ts` (duplicate `vite` under `@vitejs/plugin-react`) | `1728301699_4800d363…`, `1728373614_a833d699…`, `1728561261_6f173a51…`, `1730725818_26098135…` | Developer-facing (project dependency tree) | Soft (login lcov still produced) | None. 4 commits (late 2024); reproduces with `--frozen-lockfile`, so not an install/Node artifact. |

## Environment / setup fixes

- **`@vitest/coverage-v8` provider (events):** vitest ≥ 1 requires the coverage
  provider as a separate package. `patch-coverage.js` records it (pinned to the
  resolved vitest version) in `.coverage-providers.json`; `install-and-run.sh`
  installs it out-of-tree (`node_modules/.coverage-providers/`) and symlinks it
  into the package, keeping the frozen workspace tree untouched.
- **Frozen install:** `yarn install --frozen-lockfile --ignore-scripts` matches
  the project's CI and prevents the lockfile rewrite / dependency re-hoist that a
  non-frozen install performs.
- **Native addon `iconv` (2022-era notification):** `--ignore-scripts` skips its
  node-gyp build, so the SMS suites fail to run. `install-and-run.sh` rebuilds it
  from the Node installation's headers (Python 2.7 for Node 12/14).
- **Node heap (client):** `NODE_OPTIONS=--max-old-space-size=16384`, with inline
  per-test overrides normalised by `patch-coverage.js`, prevents the client c8
  coverage report from OOM-ing (exit 134) and dropping client lcov.
- **vitest 0.x flag handling (client, login):** vitest 0.25 has no
  `--maxWorkers` and its CLI rejects `--coverage.reporter=lcov` alongside a bare
  `--coverage`. The patch emits `--coverage.enabled=true
  --coverage.reporter=lcov` and caps parallelism via `VITEST_MAX_THREADS` /
  `VITEST_MIN_THREADS` (threads stay on, preserving per-file isolation).
- **`.dockerignore`:** whitelists `patch-coverage.js` so the project image build
  does not silently fall back to a stale cached image.

## Known gaps

- **Postinstall hook** (`node development-environment/link-ts6-api.js`): left to
  run; it may fail in the container if it expects specific paths.
- **Early-era (2020–2022) `craco test` and 2021 build failures:** not yet
  re-verified after the setup fixes; the 2021 `.error` rows above are candidates
  for a re-run.
- **Full history not yet processed:** 11643 commits remain.
# yari

**Repository:** https://github.com/mdn/yari
**Status:** active

## Test infrastructure

- **Package manager:** npm, root plus `package.json` workspaces (see
  [`config.json`](../../config.json) → `yari`).
- **Node strategy:** `use_exact_node_version = true`; override Node 18 → `18.17`
  for epoch `1676043161`–`1692619152`.
- **Runners:** `jest`, `react-scripts test` (jest-based).
- **Eras:** workspace-specific `test` scripts use either `jest` or
  `react-scripts test`; `test:testing` is jest-based but runs end-to-end tests.

## Development style

- **PR merging strategy:** Squash and merge (98.6% of first-parent commits).
- **Merge convention:** Strict `<Title> (#<PR>)`.
- **Direct commits:** Negligible (0.4% human direct commits, 33 commits).
- **JS/TS code impact of direct commits:** Negligible — release reverts and search index generation script adjustments.
- **Issue tracking discipline:** High (MDN content and platform changes are PR-reviewed and issue-linked).
- **Workflow notes:** Overwhelmingly enforced Squash & Merge across the entire 5-year history.

## Coverage collection

- **Suites collected:** workspace `test` scripts. The harness enters each
  workspace and calls the available script with coverage parameters appended.
- **Suites excluded:** end-to-end tests (`test:testing`).
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** runner coverage output is collected by
  `find-and-move-lcov.sh`.

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked (looks great)
- [x] complete run (9,082 commits processed)
- [x] complete test failure check (all failing runs labeled and assessed)
- [x] complete JEV test failure check (all failing runs evaluated; 0 pipeline issues)

## Results

Source: `stats_output/report.txt` (generated 2026-10-11 10:18).

| Metric | Value |
|---|---|
| Commits processed | 9082 |
| Without test failures | 8370 |
| With test failures | 173 |
| Not applicable | 0 |
| Hard errors | 539 |
| Coverage produced | 94.1% |

0 commits are not yet processed.

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `test viewing a simple document › render document with props should not crash` — `thrown: "Exceeded timeout of 5000 ms for a test"` (`client/src/document/index.test.tsx`); 153 runs, 2022-05-05 → 2025-09-17 | reevaluated_acceptable | valid partial (1 failing test in client suite) | None. Upstream regression introduced when `swr` was bumped from 0.5.6 to 1.3.0 (`f0c9e65dcf`), where SWR changed `initialData` to `fallbackData`. Without `fallbackData`, SWR fires `fetch` on mount, causing the unmocked fetch call to hang until Jest's default 5s timeout expires. |
| Client modal / rendering regressions — `react-modal: No elements were found for selector #root` and `Unable to find an element with the text: /Hello World!/` (`client/src/`); 9 runs | acceptable | valid partial | None. Upstream developer regressions in client modal setup and document test assertions. |
| Kumascript macro regressions — `testing the main render() function`, `test "Draft"`, `test "Deprecated_Inline"`, `test "svginfo"`, `test "spec2"` (`kumascript/tests/`); 15 runs | acceptable | valid partial | None. Upstream string formatting, slug handling, and API signature changes in Kumascript macros. |

## Environment / setup fixes

- **Jest test timeout extension (`--testTimeout=60000`):** Added `--testTimeout=60000` to Jest invocations in `install-and-run.sh` to prevent `css-syntax.test.ts` from tripping Jest's default 5-second per-test timeout while rendering 50+ CSS syntax macros under container CPU limits.
- **Pre-test build removal:** Dropped `yarn prepare-build` and `yarn build` from `install-and-run.sh`. These full-site production builds were leftovers from an excluded E2E suite (`test:testing`) and caused 98 commits to fail under `set -e` due to CRA lint-as-error in CI, Babel regenerator issues, or GitHub API scrapers.
- **Client suite runner era detection:** `install-and-run.sh` dynamically checks whether `client/scripts/test.js` exists (post-ejection era), falling back to `$REPO_ROOT/node_modules/.bin/react-scripts test` for the unified package era (Aug 2020 – May 2022) to ensure `client` coverage is collected across all eras.
- **DNS resolution and domain pinning:** Sourced `resolve-and-pin.sh` to pin `api.github.com`, `release-assets.githubusercontent.com`, `objects.githubusercontent.com`, `registry.npmmirror.com`, and `cdn.npmmirror.com` in `/etc/hosts`, avoiding `EAI_AGAIN` during postinstall binary downloads (`@vscode/ripgrep`, `@mdn/rari`) and Chinese registry mirror lookups (i.e., npmmirror URLs committed in `yarn.lock`).
- **Skip browser downloads:** Exported `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true` and `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` to skip downloading browser binaries for excluded E2E suites.

## Known gaps

None documented. A separate content repository is checked out at a
timestamp-matched commit (see `install-and-run.sh`).

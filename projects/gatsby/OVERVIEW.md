# gatsby

**Repository:** https://github.com/gatsbyjs/gatsby
**Status:** active

## Test infrastructure

- **Package manager:** npm, lerna monorepo (see [`config.json`](../../config.json) → `gatsby`).
- **Node strategy:** default.
- **Runners:** `jest`.
- **Eras:** two jest periods. Jest 27 is used before 2022-11; jest 29 is used after.

## Coverage collection

- **Suites collected:** `jest` directly. `test:coverage` runs jest with `--coverage`
  and is the main coverage script in both periods; `test` runs lint, jest, and
  peril and is not used. Collection command:
  `jest --coverage --coverageReporters=lcov --maxWorkers=1 --testTimeout=120000`.
- **Suites excluded:** `integration-tests`. These are end-to-end tests: each starts
  the real `gatsby build` or `gatsby develop` in a separate process and checks
  output files, logs, IPC messages, and exit codes without mocks. They do not
  produce library coverage. Before commit `1527e47e` (2021-04-29, "tests: isolate
  tests to tmp directory"), these tests ran under jest with
  `integration-tests/jest.config.js` (`rootDir: '../'`) and a `gatsby-dev` start
  file linked the local packages; jest produced an `lcov` file, but the gatsby
  library ran outside the jest coverage tool. They were end-to-end tests at that
  time as well.
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** jest `lcov` reporter.

## Checklist

- [x] 100 done (93/100)
- [x] failed tests doublechecked
- [ ] complete run (work in progress)
- [ ] complete test failure check

## Results

**Pending (no `stats_output`).** The legacy overview recorded, as of 2026-09-06:
4229 commits processed, 1825 without test failures, 1982 with test failures, 12
not applicable, 410 hard errors, 90.3% of applicable commits produced coverage.

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| Invalid JavaScript fixture `packages/gatsby-remark-prismjs/src/__tests__/fixtures/highlight-start-without-end.js: 'return' outside of function. (3:0)` | acceptable | none for other files; the single fixture is omitted | None. The fixture is intentionally invalid JavaScript; Babel cannot read it, so the suite exits 1 while coverage for all other files remains valid. |

### Non-critical logs

The following output is intentional and does not indicate failures:

- React prop-validation warnings (`html-renderer.js`) — the test triggers casing and
  unknown-prop warnings on purpose.
- `xhr-mock` warnings (`dev-loader.js`) — the test exercises missing-handler paths.
- `gatsby-link` external-link warnings (`index.js`) — the test checks the warning
  for external URLs in `<Link>`.
- `Failed to collect coverage from highlight-start-without-end.js` — the invalid
  fixture above; the single file is omitted.
- `gatsby-source-wordpress` 502/503/504 errors — the test exercises HTTP error
  paths.

## Environment / setup fixes

- **jest 27 + Parcel timeout.** Jest 27 does not catch `process.exit()`. Gatsby
  `reporter.panic()` runs `process.exit(1)` when Parcel fails, and Parcel compiles
  slowly in the container, so jest stopped during compilation. Fixed with
  `--testTimeout=120000`. A `process.exit` guard is retained in a comment as a
  backup.

## Known gaps

The end-to-end `integration-tests` suite is intentionally not collected.

# gatsby

**Repository:** https://github.com/gatsbyjs/gatsby
**Status:** active

## Test infrastructure

- **Package manager:** npm, lerna monorepo (see [`config.json`](../../config.json) → `gatsby`)
- **Node strategy:** default
- **Runners:** jest
- **Eras:** two jest periods: jest 27 before 2022-11; jest 29 after

## Development style

- **PR merging strategy:** Squash and merge (90.0% of first-parent commits).
- **Merge convention:** `<Title> (#<PR>)`.
- **Direct commits:** Low (9.9% human direct commits, 420 commits).
- **JS/TS code impact of direct commits:** Minimal — direct commits are almost exclusively release publications (`chore(release): Publish next`) by release maintainers.
- **Issue tracking discipline:** High (PRs link issues and changesets).
- **Workflow notes:** Monorepo strictly squashes all contributor and maintainer PRs; release scripts publish releases directly to `master`.

## Coverage collection

- **Suites collected:** unit → jest directly (`jest --verbose --coverage --collectCoverage=true --coverageReporters=lcov --maxWorkers=1 --testTimeout=30000 --forceExit`)
- **Suites excluded:** integration-tests → end-to-end tests starting real `gatsby build` or `gatsby develop` in separate processes without mocks; omitted library coverage
- **Coverage tool / config:** runner-native coverage (jest)
- **LCOV production:** jest `lcov` reporter

## Checklist

- [x] 100 done (93/100)
- [x] failed tests doublechecked (705 failing runs inspected and classified)
- [x] complete run (4,229 commits processed, 0 pending)
- [x] complete test failure check (677/677 fingerprints labeled; label DB and `report.txt` agree at 705 failing runs)
- [x] complete JEV test failure check ([`label_analysis/jev_audit.md`](label_analysis/jev_audit.md) is `current`: 526 flagged rows, 0 confirmed pipeline defects)

## Results

Source: `stats_output/report.txt` (generated 2026-10-31 12:40).

| Metric | Value |
|---|---|
| Commits processed | 4229 |
| Without test failures | 3501 |
| With test failures | 705 |
| Not applicable | 0 |
| Hard errors | 23 |
| Coverage produced | 99.5% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py gatsby --stats` (window `min`, run 2026-10-31) and
`stats_output/report.txt` (generated 2026-10-31 12:40). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 705 |
| Failing runs (label DB) | 705 (`failing runs` line) |
| Fingerprints (min / max) | 677 / 728 |
| Labeled fingerprints | 677 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 271 |
| reevaluated_acceptable | 406 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 65 / 612 |
| Labeled detections (min) | 3659/3659 (100.0%) |
| Labeled runs (min) | 705/705 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 526 flagged rows |
| Jev audit | [`current`](label_analysis/jev_audit.md) |

**State:** complete.

No `problematic` or `unclear` fingerprints remain, so no per-family table is listed.
Automated System 1 classification via Jev ([`failure_labels_jev_min.csv`](label_analysis/failure_labels_jev_min.csv))
flagged 526 rows; the attribution of every flagged family is recorded in
[`label_analysis/jev_audit.md`](label_analysis/jev_audit.md) and is not restated here.

## Environment / setup fixes

- **Babel-plugin-lodash / Istanbul TypeScript coverage AST collision (`fix_lodash_container_is_falsy`):** When `coverageDirs` was patched to include TypeScript files, Istanbul coverage instrumentation collided with `babel-plugin-lodash` / `@sigmacomputing/babel-plugin-lodash` during AST replacement of named imports, throwing `ReferenceError: <file>.ts: Container is falsy` on `js-chunk-names.ts` and `load-internal-plugins.ts`. In `install-and-run.sh`, rewriting these two files' named imports from `"lodash"` to direct submodule imports (`"lodash/kebabCase"`, `"lodash/uniqWith"`, `"lodash/isEqual"`) bypasses `babel-plugin-lodash`'s destructive AST replacement while preserving 100% full Istanbul coverage across both files and all other monorepo TypeScript files without breaking preset snapshots or mock spies. 1,442 affected runs archived to [`archive/fix_lodash_container_is_falsy/`](archive/fix_lodash_container_is_falsy/) for re-run.
- **Jest `coverageDirs` TypeScript inclusion (`fix_jest_ts_coverage`).** `jest.config.js` hardcoded `coverageDirs` to `pkgs.map(p => path.join(p, 'src/**/*.js'))`, strictly omitting all TypeScript (`.ts`/`.tsx`) files across packages throughout history (~700+ active TS files, ~32% of the codebase). Fixed in `install-and-run.sh` by dynamically patching `jest.config.js` before test execution to expand `coverageDirs` to `src/**/*.{js,jsx,ts,tsx}`. All 4,229 historical runs were archived to [`archive/fix_jest_ts_coverage/`](archive/fix_jest_ts_coverage/) for clean re-run.
- **jest 27 + Parcel timeout.** Jest 27 does not catch `process.exit()`. Gatsby `reporter.panic()` runs `process.exit(1)` when Parcel fails, and Parcel compiles slowly in the container, so jest stopped during compilation. Fixed with `--testTimeout=30000`. A `process.exit` guard is retained in a comment as a backup.
- **Windows-oriented LMDB test teardown hangs on Linux.** Gatsby's custom jest test environment (`jest.environment.ts`, introduced in `f990e082`, 2022-08-11) cleans up the LMDB stores opened by a suite. That teardown was written for Windows, where LMDB files cannot be moved or deleted while open, so it calls `await rootDb.clearAsync()` before `rootDb.close()`. On Linux `clearAsync()` never resolves: the environment teardown hangs, jest never runs its coverage reporter, and no `lcov.info` is written — the run is recorded as a hard error. The defect stays latent until `dc82d92e` (2022-10-18, "Remove LOCKED_IN feature flags") stops skipping the LMDB-store suites; hard errors then span every commit from `dc82d92e` until `62687301` (2023-01-26, "Adjust jest environment conditionally for OS"), which makes the teardown OS-conditional (clear+close on Windows; close-if-operational plus file removal elsewhere). `install-and-run.sh` backports that upstream fix at run time whenever the checked-out commit still carries the old Windows-only teardown — i.e. `jest.environment.ts` contains `clearAsync` but not the fix's `isOperational` guard. Scope: `(f990e082, 62687301)`, self-limiting to the commits that carry the defect.
- **Git remote origin URL alignment.** Prior to upstream commit `ba7d505b84`, `sampleSiteForExperiment` hashed unmocked git repository information (`getRepositoryId().repositoryId`). The snapshot was authored on a developer clone with `remote.origin.url` set to the standard GitHub SSH URL (`git@github.com:gatsbyjs/gatsby.git`). Setting `git config remote.origin.url "git@github.com:gatsbyjs/gatsby.git"` in `install-and-run.sh` reproduces the expected murmurhash bucket calculations without modifying any project code or tests.
- **Contentful unmocked CDN image test pre-population.** Between commits `f5dab4f5ac` and `94ddb6bade` (Aug–Nov 2021), `packages/gatsby-source-contentful/src/__tests__/extend-node-type.js` issued live HTTP requests to `images.ctfassets.net` and strictly compared base64 output. Upstream changes to CDN compression over time caused live downloads to diverge from the test's static expectations. The expected base64 string evolved from `CAUMNjFcK/NJ` to `CBQANxNx70py` on commit `4ef84376be` before adopting a regex in commit `1d8ebb2588`. Because `extend-node-type.js` consults `.cache/remote_cache/images/<sha1>.base64` before issuing network requests, `install-and-run.sh` dynamically checks the test assertion and pre-populates the cache with the exact expected payload. Re-run completed; test failures eliminated.
- **Gatsby worker pool CPU capping.** On high-core host hardware (e.g. 256 CPUs), Gatsby's query worker pool scales to `os.cpus().length` and opens hundreds of concurrent reader transactions into the LMDB datastore during bootstrap builds (`gatsby-admin`), exceeding LMDB's default `maxReaders` table limit (126) with `MDB_READERS_FULL`. Sourced from Gatsby's official CI setup (`.circleci/config.yml`), `export GATSBY_CPU_COUNT=2` in `install-and-run.sh` caps worker pool creation and prevents LMDB reader exhaustion across 62 commits (Sep 2021).
- **Puppeteer Chromium download skip.** In late 2022 / early 2023 commits, dependency updates pulled in `puppeteer`, whose postinstall script attempts to download Chromium from Google Cloud Storage (`storage.googleapis.com`). Because pipeline containers intentionally lack unrestricted internet access, the download fails with `EAI_AGAIN`. Setting `export PUPPETEER_SKIP_DOWNLOAD=true` in `install-and-run.sh` bypasses the browser download cleanly as Chromium is not needed for unit tests.
- **LMDB datastore flag (`fix_lmdb_datastore_flag`).** Between 2022-06-28 and 2022-10-18 Gatsby selected the LMDB datastore only when `GATSBY_EXPERIMENTAL_LMDB_STORE` was set, and upstream CI exported it (`.circleci/config.yml`). The pipeline never did, so the suite ran on the in-memory datastore, which holds nodes strongly; the `WeakRef`-based `works correctly if GC happen mid running` tests could therefore never pass and failed on all 388 commits of that window. `install-and-run.sh` now exports `GATSBY_EXPERIMENTAL_LMDB_STORE=1` whenever the checked-out commit still contains that test, leaving every other era untouched. 388 runs archived to [`archive/fix_lmdb_datastore_flag/`](archive/fix_lmdb_datastore_flag/).
- **Webfonts DNS pinning (`fix_webfonts_dns`).** `gatsby-plugin-webfonts` runs `onPreBootstrap` during the `gatsby` package's postbuild and downloads the stylesheet and font files. Containers lose DNS after enough resolution attempts, and `fonts.googleapis.com` / `fonts.gstatic.com` then failed with `EAI_AGAIN`, aborting the install phase before any test ran. `install-and-run.sh` now pins both hosts via `resolve_and_pin`. 23 runs archived to [`archive/fix_webfonts_dns/`](archive/fix_webfonts_dns/).
- **Flaky LMDB reader-slot race and MSW interception gap (`rerun_lmdb_rslot_and_msw_race`).** Two independent flaky setup artifacts, each affecting a small number of runs in 2022-07–2022-09: (1) `MDB_BAD_RSLOT: Invalid reuse of reader locktable slot` — a native LMDB reader-slot reuse race introduced with lmdb 2.5.3, firing in 5 of 134 runs in the era; (2) Shopify `EAI_AGAIN` DNS failure — an MSW interception gap in `source-from-operation.ts` that lets a GraphQL request reach the network, firing in 4 runs. Both are environment-level flakes, not commit-era regressions. 9 runs archived to [`archive/rerun_lmdb_rslot_and_msw_race/`](archive/rerun_lmdb_rslot_and_msw_race/) for re-run.

## Known gaps

The end-to-end `integration-tests` suite is intentionally not collected.

The following output is intentional and does not indicate failures:

- React prop-validation warnings (`html-renderer.js`) — the test triggers casing and unknown-prop warnings on purpose.
- `xhr-mock` warnings (`dev-loader.js`) — the test exercises missing-handler paths.
- `gatsby-link` external-link warnings (`index.js`) — the test checks the warning for external URLs in `<Link>`.
- `Failed to collect coverage from highlight-start-without-end.js` — `packages/gatsby-remark-prismjs/src/__tests__/fixtures/highlight-start-without-end.js` is an intentionally invalid JavaScript fixture; the single file is omitted.
- `gatsby-source-wordpress` 502/503/504 errors — the test exercises HTTP error paths.

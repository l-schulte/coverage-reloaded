# apostrophe

**Repository:** https://github.com/apostrophecms/apostrophe
**Status:** active

## Test infrastructure

- **Package manager:** npm (single-package era); pnpm in the monorepo era (from
  2025-12-01) (see [`config.json`](../../config.json) → `apostrophe`). Detection
  reports `pnpm@>=8` for pre-monorepo commits carrying a `pnpm-lock.yaml`
  (2025-10-20 → 2025-11-30); those commits have no `packageManager` field, so
  `execute.sh` installs pnpm from WayPack at the commit timestamp.
- **Node strategy:** default (per commit; Node 14–24 over the window).
- **Runners:** mocha with nyc.
- **Eras:**
  - 2021-01-01 → 2021-08: root `test` = `nyc --reporter=html mocha`.
  - 2021-08 → 2024-01: root `test` = `nyc --reporter=html mocha -t 10000`.
  - 2024-01 → 2024-10: splits `test/assets.js` into a second nyc run.
  - 2024-10 → 2025-09: adds the `test/esm-project/esm.js` smoke run.
  - 2025-09 → 2025-11-18: drops `--reporter=html`.
  - 2025-11-18 → 2025-11-30: adds the `add-missing-schema-fields-project` nyc run.
  - 2025-12-01 →: pnpm monorepo; `packages/apostrophe` exposes `test:base`,
    `test:missing`, `test:assets`, `test:esm`.

## Coverage collection

- **Suites collected:** each nyc command in the root `test` chain, labelled
  `test` (unlabelled root run), `base` (`--ignore=test/assets.js`), `assets`, and
  `missing`; in the monorepo era, `packages/apostrophe` `test:base`,
  `test:missing`, `test:assets`.
- **Suites excluded:** the `test:esm` smoke run (no nyc, no LCOV).
- **Coverage tool / config:** the project's own nyc; `.nycrc` sets 100%
  thresholds but `check-coverage` is false, so they are inert.
- **LCOV production:** every collected suite runs as
  `nyc --reporter=lcov --reporter=text …`; `find-and-move-lcov.sh` collects
  `coverage/lcov.info` (with workspace-relative prefixes in the monorepo era).

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked (non-zero-exit runs inspected and classified)
- [x] complete run (5,553 commits processed)
- [x] complete test failure check (all failing runs classified; 0 unclear remain)
- [x] complete JEV test failure check (120 signatures evaluated; 2 flagged uploadfs fallbacks audited and confirmed benign)

## Results

Source: `stats_output/report.txt` (generated 2026-10-01 09:37).

| Metric | Value |
|---|---|
| Commits processed | 5553 |
| Without test failures | 4879 |
| With test failures | 526 |
| Not applicable | 64 |
| Hard errors | 84 |
| Coverage produced | 98.5% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `Attachment > insert > should upload a text file…` — `assert(fs.existsSync(t))` (`test/attachments.js:68`); 95 commits, 2021-08-09 → 2021-12-06 | problematic | valid partial; one `it` aborts | None. Upstream `uploadfs` < 1.18.5 `copyFile` race: when the destination directory is missing, the retried copy is still in flight while the original stream's `close` fires success, so `insert()` resolves before the file exists. Fixed in `uploadfs` 1.18.5 (2021-12-07); apostrophe pinned `^1.17.1` until 2023. |
| `Schema builders` — `can obtain choices for _cats/_favorites` (`cats.length === 9`, `test/schemaBuilders.js:178,242`); 61 commits, 2021-06-04 → 2021-06-10 | acceptable | valid partial (4 failing) | None; developer-facing assertion at that commit era. |
| `Admin bar` — group order/count (`7 !== 6`, `test/admin-bar.js:44,81`); 64 commits, 2021-04-15 → 2025-11-20 | acceptable | valid partial (2 failing) | None. |
| `Schemas` — required string field (`test/schemas.js:1758`); 19 commits, 2021-01-27 → 2021-02-16 | acceptable | valid partial (1 failing) | None. |
| `Pieces` — `._url` population (`test/pieces-page-type.js:91,118`); 19 commits, 2021-08-06 → 2021-08-24 | acceptable | valid partial (2 failing) | None. |
| `Pages` — cache-control/etags (`test/pages.js:671`); 33 commits, 2022-04-06 → 2022-04-26 | acceptable | valid partial (1 failing) | None. |
| `Widgets` — placeholders (`test/widgets.js:284,294,302`); 3 commits, 2023-01-04 → 2023-01-05 | acceptable | valid partial (3 failing) | None. |
| `Locales` / `Pages` / `Soft Redirects` / `static i18n` — expected 404, got 500/other (WIP merge `78be2e2a`, 2023-02-27); 1 commit | acceptable | valid partial (10 failing) | None; same-day sibling `caa9a916` passes. |
| `Translation` — browser data / `beforeLocalize` (`test/translation.js:169,201,234`); 37 commits, 2024-02-19 → 2024-03-03 (`base`) | acceptable | valid partial (3 failing) | None. |
| `assets` bundles — `Can't resolve 'floating-vue'`; 7 commits, 2023-11-13 → 2023-11-28 | acceptable | hard error; no coverage | None. Broken intermediate commits between the import switch and the dependency declaration. |
| `Pages REST` / `Job module` — `Error: HTTP error 404` (`modules/@apostrophecms/http/index.js`); 10 runs, 2021-01-05 → 2023-03-30 | acceptable | valid partial | None. In-flight developer bugs causing 404s (e.g. undeclared `_id` in `page.post()` in `b272ac63`, broken `loginAs` wrapper in `d284a8b3`); promptly fixed in follow-up commits. |

> Mocha's exit code equals the number of failing tests (2/3/4/10 observed), not a
> crash signal; `find-and-move-lcov.sh` records any non-zero as a test failure.

## Environment / setup fixes

- **MongoDB engine selection:** MongoDB 4.4 for the driver-3.x era (before
  2024-04-04) and 7.0 after; both installed from official tarballs.
- **DAC capability drop:** suites run under
  `setpriv --bounding-set=-dac_override,-dac_read_search`, so `uploadfs.disable`
  (chmod 0000) is enforced as for the project's non-root CI.
- **Locale host pins:** `ca.localhost` and `en.localhost` mapped to `127.0.0.1`
  in `/etc/hosts` (bullseye glibc 2.31 resolves `*.localhost` only to `::1`).
- **pnpm install:** `--no-frozen-lockfile` (lockfiles are gitignored).
- **Private Pro dependency:** the 2025-12-01 monorepo switch declared
  `@apostrophecms-pro/automatic-translation` (private `git+ssh`) as an
  `import-export` devDependency. `install-and-run.sh` drops it before
  `pnpm install` unless `TEST_WITH_PRO` is set; only `packages/apostrophe` suites
  are collected.
- **ImageMagick:** installed in the project `Dockerfile` as uploadfs's documented
  fallback processor (probes `PATH` for `identify`) when sharp fails to install.
- **stylelint GitHub dependency:** for 2024-05-28 → 2024-06-12, `package.json`
  pinned `stylelint-config-apostrophe` to an unpinned `github:` spec; `npm` clones
  default-branch HEAD, whose newer dependency set WayPack cannot serve. The
  lint-only devDependency is dropped before `npm install`.
- **Suite timeout extension (`TEST_TIMEOUT=60000` & Moore's Law scaling):**
  `install-and-run.sh` exports `TEST_TIMEOUT=60000` so suites relying on `t.timeout`
  (such as `test/workspaces-project.js` which runs `npm install` in a subprocess, and
  `test/images.js`) have sufficient headroom under container virtualization.
  Additionally, for `test/login.js` and `test/users.js` which hardcoded `this.timeout(20000)`,
  `install-and-run.sh` surgically increases their timeouts to 60s via `sed` to compensate
  for `credential`'s PBKDF2 iterations escalating from ~1.7M (~0.9s/hash) in 2021 to over
  10.6M iterations (~5.5s/hash) in 2026.
- **GitHub asset DNS pins:** `resolve-and-pin.sh` pins `release-assets.githubusercontent.com`,
  `objects.githubusercontent.com`, and `codeload.github.com` to prevent transient `EAI_AGAIN`
  errors when dependencies (such as `node-sass`) download prebuilt binary addons.

## Known gaps

The full history has been processed (5,553 commits). Broken intermediate commits
(such as undeclared `floating-vue`) have their coverage withheld by the
`mocha_check_passing` guard rather than recorded as misleading partial results. A
developer-committed `.only` in `test/docs.js:1150` (`1712065734`, 2024-04-02) is
classified as not-applicable via `na_if_focus_marker` (see
[`STUDY_DECISIONS.md`](../../STUDY_DECISIONS.md) §2), since a forgotten focus
marker is not the same category of error as a broken dependency. `--forbid-only`
is retained in the mocha command only as a backstop for markers outside the
scanned suite roots. Failure labels are fully classified in
`failure_labels_project.csv` with zero remaining unclear rows.

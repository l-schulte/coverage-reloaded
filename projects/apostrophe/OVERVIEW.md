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
- [ ] complete run (5,453 commits remaining)
- [ ] complete test failure check (failure labels not yet generated)

## Results

Source: `stats_output/report.txt` (generated 2026-09-13 15:25).

| Metric | Value |
|---|---|
| Commits processed | 100 |
| Without test failures | 82 |
| With test failures | 16 |
| Not applicable | 0 |
| Hard errors | 2 |
| Coverage produced | 98.0% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `Attachment > insert > should upload a text file…` — `assert(fs.existsSync(t))` (`test/attachments.js:68`); 9 commits, 2021-08-20 → 2021-11-08 | problematic | valid partial; one `it` aborts | None. Upstream `uploadfs` < 1.18.5 `copyFile` race: when the destination directory is missing, the retried copy is still in flight while the original stream's `close` fires success, so `insert()` resolves before the file exists. Fixed in `uploadfs` 1.18.5 (2021-12-07); apostrophe pinned `^1.17.1` until 2023. |
| `Schema builders` — `can obtain choices for _cats/_favorites` (`cats.length === 9`, `test/schemaBuilders.js:178,242`); 1 commit (2021-06-08) | acceptable | valid partial (4 failing) | None; developer-facing assertion at that commit. |
| `Admin bar` — group order/count (`7 !== 6`, `test/admin-bar.js:44,81`); 1 commit (2021-04-22) | acceptable | valid partial (2 failing) | None. |
| `Schemas` — required string field (`test/schemas.js:1758`); 1 commit (2021-01-27) | acceptable | valid partial (1 failing) | None. |
| `Pieces` — `._url` population (`test/pieces-page-type.js:91,118`); 1 commit (2021-08-24) | acceptable | valid partial (2 failing) | None. |
| `Pages` — cache-control/etags (`test/pages.js:671`); 1 commit (2022-04-26) | acceptable | valid partial (1 failing) | None. |
| `Widgets` — placeholders (`test/widgets.js:284,294,302`); 1 commit (2023-01-04) | acceptable | valid partial (3 failing) | None. |
| `Locales` / `Pages` / `Soft Redirects` / `static i18n` — expected 404, got 500/other (WIP merge `78be2e2a`, 2023-02-27) | acceptable | valid partial (10 failing) | None; same-day sibling `caa9a916` passes. |
| `Translation` — browser data / `beforeLocalize` (`test/translation.js:169,201,234`); 1 commit (2024-02-28, `base`) | acceptable | valid partial (3 failing) | None. |
| `assets` bundles — `Can't resolve 'floating-vue'` (`1699901271`, 2023-11-13) | acceptable | hard error; no coverage | None. Broken intermediate commit between the import switch and the dependency declaration. |
| `.only` forbidden by `--forbid-only` in `test/docs.js:1150` (`1712065734`, 2024-04-02) | acceptable | hard error; no coverage | None; developer-committed `.only`, aborted by design to avoid subset coverage. |

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

## Known gaps

The full history is not yet processed (5,453 commits). Two hard errors remain, both
developer-facing (undeclared `floating-vue`; a committed `.only`); their coverage
is withheld by the `mocha_check_passing` guard rather than recorded as misleading
partial results. Failure labels have not been generated
(`failure_labels_project.csv` is absent), so the non-zero-exit runs are classified
from manual log inspection only.

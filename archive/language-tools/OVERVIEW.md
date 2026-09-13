# language-tools

**Repository:** https://github.com/prisma/language-tools
**Status:** archived

## Test infrastructure

- **Package manager:** pnpm / npm / yarn (priority); the `package_manager_priority` override was removed from [`config.json`](../../config.json) on archival.
- **Node strategy:** default
- **Runners:** mocha, nyc, vitest (language-server); jest, vitest (scripts)
- **Eras:**
  - Package manager: npm with workspaces and lerna (2021-01-04 → 2025-12-05; a
    transient pnpm window covers 2022-03-31 → 2022-04-01) → pnpm with turbo
    (2025-12-05 → present).
  - language-server unit suite: mocha on compiled `dist` (2021-01-04 →
    2022-07-18) → nyc + mocha (2022-07-19 → 2024-05-14) → vitest with
    `@vitest/coverage-v8` (2024-05-15 → present). The test directory moves from
    `dist/src/test` to `dist/src/__test__` at 2022-03-23.
  - scripts suite: root `jest.config.js` from 2021-09-30 (coverage config from
    2022-07-19) → `scripts/vitest.config.mjs` from 2025-12-17.
  - VS Code extension suite: `jest` unit tests (2021-01-04 → 2021-08), then the
    extension-host integration suite via `@vscode/test-electron` (`test:e2e` /
    `test:integration`, 2021-08-19 → present), with Playwright UI tests added
    from 2025-02.

## Coverage collection

- **Suites collected:** `unit` (packages/language-server); `scripts-tests` (root
  `scripts/__tests__`, emitted under suite labels `jest` or `vitest`).
- **Suites excluded:** the VS Code extension suite — `test:e2e` / `test:e2e:vsix`
  / `test:e2e:bump`, `test:integration` (`@vscode/test-electron`, runs inside a
  downloaded VS Code extension host), and `test:playwright` (UI). The project
  does not instrument or upload coverage for the `packages/vscode` workspace:
  `.github/codecov.yml` defines `scripts` and `language-server` flags and leaves
  the `vscode` flag commented out (since `ecb733557`, 2022-07-19), and the
  package has no c8/nyc or coverage configuration.
- **Coverage tool / config:** project-configured nyc (2022-07-19 → 2024-05-14)
  and vitest v8 coverage (2024-05-15 → present); the pre-nyc mocha era is wrapped
  with `nyc@15` (Verdaccio); jest configs predating 2022-07-19 are forced with
  `--coverage`.
- **LCOV production:** coverage reporters (`clover`, `lcov`) write `lcov.info`,
  then `find-and-move-lcov.sh` moves it to `$COVERAGE_REPORT_PATH`. Native
  `prisma-fmt` engine downloads (2021-01 → 2021-12) are routed through the
  WayPack `/request/` cache.

## Checklist

- [ ] 100 done (0/100)
- [ ] failed tests doublechecked (no runs classified)
- [ ] complete run (not started; `output/` empty)
- [ ] complete test failure check (no labels)

## Results

Pending — no `stats_output/report.txt`; `output/` is empty (no commits collected
yet).

## Known test failures

None classified. `failure_labels_project.csv` is not present.

## Environment / setup fixes

- `package_manager_priority: [pnpm, npm, yarn]` in `config.json` corrected
  `yarn@1` misclassification for 2025-05 → 2025-11, where a stray root `yarn.lock`
  coexisted with `package-lock.json`.
- Native `prisma-fmt` downloads were proxied through WayPack `/request/`; the
  mocha default hook timeout otherwise skipped the completion suite and left a
  non-executable binary (exit code `EACCES`).
- `jest.config.js` before 2022-07-19 has no coverage configuration; coverage is
  forced via CLI so the scripts suite yields an LCOV file.

## Archive decision

`packages/vscode/src` (43 files, ~4,038 lines at HEAD) is exercised only by the
VS Code extension-host integration suite, which runs inside a downloaded VS Code
install and is not instrumented by the project. Collecting it would require
either:

- actively excluding the whole `packages/vscode/src` subtree from the study, or
- instrumenting the extension host: Xvfb plus a lightweight desktop (the archived
  harness notes that `--headless` segfaults for some commits), Electron runtime
  libraries, Chromium, and the VS Code download routed through WayPack
  `/request/`.

Excluding a whole code section is not feasible for the study, and instrumenting
the extension host was judged not worth its cost and instability. The project is
archived for this reason.

A prior attempt at the extension-host pattern exists at
`archive/aws-toolkit-vscode` (`Xvfb`, `desktop-lite-debian.sh`,
`desktop-init.sh`, Chromium, `c8`, and VS Code cached via WayPack `/request/`).

## Known gaps

- Full commit history not collected.
- `packages/vscode/src` uncovered; see Archive decision.
- vitest v8 coverage emits a line entry per source line (including blanks and
  comments), whereas nyc counts executable lines; line counts are not directly
  comparable across the 2024-05 tooling switch.

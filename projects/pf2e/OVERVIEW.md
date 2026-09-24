# pf2e

**Repository:** https://github.com/foundryvtt/pf2e
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `pf2e`).
- **Node strategy:** `node_version_lts_offset_months = 1`.
- **Runners:** `jest`.
- **Eras:** a single `test` command, always `jest`. No `test` script exists before
  2020-04-22. From the earliest commits a `pretest` lint gate (`eslint`, later
  `npm run lint`) and a `posttest` betterer gate run around jest.

## Coverage collection

- **Suites collected:** `test`, with `--coverage` appended.
- **Suites excluded:** none.
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** runner coverage output is collected by
  `find-and-move-lcov.sh`.

## Checklist

- [x] 100 done (97/100)
- [x] failed tests doublechecked (49 exit-code-1 runs: 32 betterer quality-gate, 17 jest)
- [x] complete run (full history processed on committer date)
- [x] complete test failure check (all 61 failure fingerprints across 49 runs labeled)

## Results

Source: `stats_output/report.txt` (generated 2026-09-16 09:13).

| Metric | Value |
|---|---|
| Commits processed | 27992 |
| Without test failures | 27903 |
| With test failures | 49 |
| Not applicable | 0 |
| Hard errors | 40 |
| Coverage produced | 99.9% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

All failing runs exit with code 1 and valid (partial) coverage; the suite never
bails. See [`failure_labels_project.csv`](failure_labels_project.csv) for the full
labels (deduplicated per failure fingerprint; `occurrences` counts the runs
sharing a fingerprint).

### Betterer quality-gate exit code 1 — not test failures (32 runs)

These runs must not be mistaken for test failures. `posttest` runs
`betterer --strict` after `jest`; when a commit raises strict-TypeScript/ESLint
issue counts against the committed `.betterer.results` snapshot, betterer throws
and `npm test` exits 1 — while **all jest tests passed** (for example, "17
passed, 0 failed"). Coverage is unaffected: the jest run completes, so the lcov
reflects the full behavioral run.

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `🔥 stricter compilation: "stricter compilation" got worse. (N issues) 😔` and `☀️  betterer  erro  🔥  - …` — `betterer --strict` regressions across 32 runs (2021-01 to 2021-09) | false_positive | none; the jest run fully passed, so the lcov reflects the complete behavioral run | None. A code-quality regression at that commit, not a test failure. Do not relabel as environment. |

### Jest behavioral failures (17 runs)

Genuine dev-facing failures; the developer at that commit would have seen the
same error.

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `TypeError: game.actors is not iterable` — `tests/module/migration.test.ts` fails 13 tests at `28fbe73057e` (2021-04-12, "Update migration runner to operate on world compendia") | reevaluated_acceptable | valid partial | None. `migration-runner.ts` iterates `game.actors` while the test mock is still the non-iterable `{entities, get, has}`; the next commit `7e83ae3e1e0` swaps in the iterable `FakeEntityCollection`. |
| `● Test suite failed to run` — ts-jest compile errors in `src/module/item/treasure.ts` (`TS2344` / `TS2339`) at `ffadc44356f` (2021-02-13) | reevaluated_acceptable | valid partial | None. Mis-typed `game.packs.find<PF2EPhysicalItem>`; fixed the same day in `52421b542ce`. |
| `● Test suite failed to run` — suite-level compile/load errors (`ReferenceError: foundry is not defined`, `PredicatePF2e is not defined`, `SyntaxError: Unexpected string in JSON`) across 8 runs (2021-05 to 2024-04) | acceptable | valid partial | None. Dev-facing transitional-compile failures. |
| `● should calculate wealth based on inventory › sell …` — assertions in `tests/module/item/treasure.test.ts` (2021-05) | acceptable | valid partial | None. Dev-facing assertion failure. |

## Environment / setup fixes

None.

## Known gaps

Forty commits (0.14%) are hard errors: no `lcov.info` was produced. See
[`output/`](output/) (`*.error`) and [`logs/`](logs/) (`*.error`) for the
per-commit evidence.

| Signature | Count | Cause | Coverage impact | Action |
|---|---|---|---|---|
| `pretest` lint failure (`eslint` / `prettier`) — `npm ERR! Test failed` before jest runs | 37 | The commit's `pretest` lint gate exits non-zero, so `npm test` aborts before jest executes and no `lcov.info` is emitted (2021-02 to 2021-10) | none produced; commit uncollected | None. Developer-facing lint errors at those commits, not an environment artifact. |
| `install-and-run.sh timed out after 5400s (90 minutes)` | 2 | Late-era `pretest` lint overruns the 90-minute budget (2023-11, 2024-06) | none produced; commit uncollected | Re-run if a smaller worker budget helps; otherwise accept. |
| `npm ERR! code ERR_SOCKET_TIMEOUT` during install | 1 | Transient network timeout reaching WayPack (2022-10) | none produced; commit uncollected | Re-run. |

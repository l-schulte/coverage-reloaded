# Jev audit — moodleapp

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode), audit
written 2026-10-21
**Snapshot:** mode `fingerprint`; rows `70`; flagged `is_pipeline_issue == True` `17`
(`runner_env_config`: `15`, `module_resolution`: `2`); Jev `labeled_at` max
`2026-10-21T18:26:57.260077+00:00`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max
`2026-10-21T18:26:24.792620+00:00`; fingerprints `70`)

Jev rows (70) equal the human fingerprint count (70), and the Jev `labeled_at` maximum
postdates the human one, so the Jev file postdates the last human labeling pass. The 17
flagged fingerprints cover 58 union runs of the 116 failing runs.

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| A — jest globals missing from the dependency tree (TS2593 `Cannot find name 'describe'`, TS2304 `Cannot find name 'fail'`) | 2021-07-27 `655e97213dfc` (`1627386228`), window to 2021-08-09, 8 union runs | 13 | `runner_env_config` | `tsconfig.test.json` declares `"jest"` in `types` and `src/testing/setup.ts` uses jest globals, but `package-lock.json` holds 0 `@types/jest` entries across the window (no direct dependency either); `npm ci` therefore installs a tree without jest typings. Upstream recovers in the same session: last failing run `c6a90e251` (2021-08-09 12:00:39) fails 13/13 suites with a 0-entry lock, and the immediately following commit `f7eac3298` (Revert "MOBILE-3833 config: Update to angular 11", 12:00:53) restores 3 `@types/jest` lock entries and passes 13/13 suites (`logs/1628503253_f7eac3298…log`). | upstream defect |
| B — import of a file the commit never added | 2022-03-01 `717978388e0` (`1646131677`), 1 union run | 2 | `module_resolution` (1), `runner_env_config` (1) | `MOBILE-3982 core: Extract CoreComponentsRegistry` makes `src/core/services/utils/dom.ts:55` import `@singletons/components-registry`, but `src/core/singletons/components-registry.ts` does not exist anywhere in that tree → jest `Configuration error: Could not locate module @singletons/components-registry mapped as …/src/core/singletons/$1`. The child commit `6b5d1db43` (same day, committed 12:09 vs 11:50) adds the missing file (53 lines). | upstream defect |
| C — new ESM dependency not covered by the project's jest transform config | 2023-04-21 `a0d49dc5e02` (`1682050666`), 1 union run | 1 | `runner_env_config` | `MOBILE-4214 pushnotifications: Add public key registration` swaps `@ionic-native/push` for `@moodlehq/ionic-native-push`; jest fails with `SyntaxError: Cannot use import statement outside a module` on `node_modules/@moodlehq/ionic-native-push/ngx/index.js` because `transformIgnorePatterns` excludes only `@ionic-native|@ionic`. Upstream fixes it on 2023-04-26 in `e56a47e35` (same `MOBILE-4214` ticket), adding `@moodlehq` to `transformIgnorePatterns`. | upstream defect |
| D — Ionic 7 migration removed a dependency still imported by source | 2023-11-09 `22d0d4ece1f8` (`1699544907`), window to 2023-12-04, 48 union runs | 1 | `module_resolution` | `MOBILE-3947 app: Upgrade to Ionic 7` (`dbb3db08a`) removes `@ionic-native/qr-scanner` from `package.json` **and** `package-lock.json` while `src/core/singletons/index.ts` still imports `@ionic-native/qr-scanner/ngx` → TS2307 on every processed commit of the migration (72 suites fail per run; a TS2345 `ComponentFactoryResolver` variant shares the window). The dependency cannot be installed by `npm ci` from that lockfile, which excludes a pipeline install defect by construction. Upstream removes the import in `c0ae3e61c` ("qr-scanner: Create qr scanner service") and adjusts test configuration in `b0f8f73f8`. Largest family: 48 of the 58 flagged union runs. | upstream defect |

## Conclusion

0 confirmed pipeline defects; 4 confirmed commit-era (upstream) defect families covering
all 17 flagged fingerprints and all 58 flagged union runs. No Jev flag traces to the
container, the harness, or the registry mirror.

All four families are compile-time failures: jest executes no test at all, reports
`Tests: 0 total`, and still emits an all-zero `lcov`. They account for 59 of the 67
runs in the project that executed zero tests (families A 9, B 1, C 1, D 48); the
remaining 8 belong to earlier compile-error families recorded in the overview. Every
zero-test run is a merged side-branch commit; the first-parent mainline carries none.

Jev's `env_subsystem` attribution (`runner_env_config`, `module_resolution`) is wrong in
all 17 rows: every flagged failure is a defect in the committed tree or the committed
test configuration, not in our runner environment. This is an expected limitation of a
stateless log evaluator and is recorded as a calibration signal for future Jev runs; it
has no effect on the human labels.

## Label outcome

Remaining `acceptable`: 1 (`8949e9ddc9cda88c`, family C). Reclassified
`reevaluated_acceptable`: 16 (families A, B, D). Remaining `problematic`: 0 — no work
order is required, and no `install-and-run.sh` or `Dockerfile` change is recommended.

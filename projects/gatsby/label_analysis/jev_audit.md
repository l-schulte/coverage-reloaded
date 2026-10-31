# Jev audit — gatsby

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)
**Snapshot:** mode `fingerprint`; rows `677`; flagged `is_pipeline_issue == True` `526`
(`missing_build_step`: `244`, `runner_env_config`: `205`, `none`: `73`,
`module_resolution`: `4`); Jev `labeled_at` max `2026-10-31T12:03:10.609712+00:00`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max
`2026-10-30T14:36:47.242902+00:00`; fingerprints `677`)

Dataset: 705 failing runs, 3,659 detections, no `.error` overlap — every flagged
fingerprint belongs to a run that already produced `unit.lcov`.
Project inclusion at audit time: 4,206 / 4,229 commits with coverage (99.5 %), 23 `.error`.

Jev flagged 526 of 677 fingerprints; human labels contain 0 `problematic`
(406 `reevaluated_acceptable`, 271 `acceptable`). Agreement 151/677 (22 %).

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| `//.cache/schema.gql` ENOENT cascade (A) | 2021-09-14 `1631612626_f8c5141b` | 441 (334 ENOENT + 56 `_fsExtra` + 51 schema-undefined + rest) | missing_build_step / runner_env_config / none | v4 pre-major bump left `program.directory` empty → writes to `//.cache`. `b622b22e3a` *implement shouldGenerateEngines (#33175)* 14:34, fixed by `4712acc619` *adjust tests after the bump (#33171)* 18:03. 3 adjacent runs, ~2.5 h. | upstream defect |
| Parcel `compileGatsbyFiles` 15 s hooks (D1/D2) | 2022-06-28 `1656399324_69824f67` | 10 | runner_env_config | `compile-gatsby-files.ts:16` sets `jest.setTimeout(15000)`, overriding our `--testTimeout=30000`. 2022-06 19/30, 2022-07 49/52 after `2acc6ed3c5` (retry loop, `RETRY_COUNT=5`, `50·2^n` backoff); collapses after `9d737b6218` (2022-08-18); ends when `0a80cd6d61` (2024-01-09) raises it to `60_000`. Residual 2023 rate 25–35 %. | upstream defect; pipeline amplifier unverified |
| `gatsby-worker` `write EPIPE` (D4) | 2022-06-30 `1654538709_8257bca2` | 4 | none | `packages/gatsby-worker/src/index.ts:348` sends on a channel whose child already exited; no `worker.connected` guard, `EPIPE` unhandled. Still firing 2025-12. | upstream defect |
| `fetch-remote-file` got `TimeoutError` (D3) | 2021-09-15 `1631715933_497d5070` | 2 | none | `jest.useFakeTimers()` + `runAllTimers()` mid-flight fires got's 30 s send timeout inside msw. File rewritten `19b0304e0a`/`98f2dfc14c` (2022-02/03); last failure 2022-01-13. | upstream defect |
| `worker (jobs)` 35 s hook (D5) | 2022-01-03 `1641222842_33049c8e` | 13 | runner_env_config | single run, never repeated in 4 years. | unclear (one-off) |
| `getCIName is not a function` (B) | 2021-02-19 `1613748275_c0ab1959` | 11 | module_resolution / none | `__tests__/handle-flags.ts` partial-mocks `gatsby-core-utils` with `{ isCI }` only; transitive `gatsby-telemetry/lib/repository-id` needs `getCIName`. Rate ~1–3 %/month until 2022-09, ~25–30 % after. | upstream defect (test mock) |
| `Nock: Disallowed net connect "external.com:80/dog.jpg"` (C) | 2022-03-01 `1646171831` | 1 | none | Exactly bracketed by `29b236b7f2` *add support for image-cdn (#34825)* and `3f1254492b` (2022-04-06) fix. Every run in the 5-week window. | upstream defect |
| `worker can access node created in main process` (E) | 2022-07-06 `1657088012_4e5f42d0` | 2 | none | `Expected {…"shared-node"…}` / `Received: null`, `datastore.ts:75`. Flat 10–20 %/month 2022-07 → 2025-08; higher in 2023-04/05 than during our `GATSBY_EXPERIMENTAL_LMDB_STORE` window, so our flag is not the driver. | upstream defect |
| Other `Cannot read properties of undefined` (F) | 2021-09-14 | 103 | missing_build_step / runner_env_config / none | 96 % is the A cascade seen through a bare `TypeError`; remainder in the C window. Jev's `missing_build_step` label is a false positive. | upstream defect (duplicate of A) |
| Long tail (G) | 2021-09-14 / 2022-03 | 13 | mixed | `Joi.subPlugins`, `ENOENT 'wat'`, `get-page-data-util` belong to A; `Your test suite must contain at least one test` to C; `WorkerBackend is not a constructor` and `anyToDiagnostic` are single runs. | upstream defect (duplicate) |

## Conclusion

Zero of Jev's 526 `problematic` fingerprints traces to the container, harness, or
registry mirror. Every family maps to a dated upstream commit window or an upstream
test race, and none overlaps the 23 `.error` commits, so no work order here recovers
coverage — the exposure variable for gatsby is already complete at 99.5 %.

One item is left open rather than closed: the residual 25–35 % Parcel hook timeout
rate in 2023 (D1). `@parcel/workers` sizes its farm as
`PARCEL_WORKERS || ceil(lscpu physical cores / 2)`, which is 64 processes per
container on the 128-core host and is not capped by `GATSBY_CPU_COUNT` or by any
`container_cpus` setting. `PARCEL_WORKERS=2`, gated on the Parcel test file's
presence, is the experiment that would confirm or discard it.

## Label outcome

Remaining `acceptable`: 271. Reclassified `reevaluated_acceptable` during this
audit: 0 (no changes to `failure_labels_project_min.csv`). Remaining `problematic`:
0. Jev's 526 flags resolve to 0 confirmed pipeline defects; the audit is recorded
here and no work order is opened.

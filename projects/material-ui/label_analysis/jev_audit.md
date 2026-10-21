# Jev audit — material-ui

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)
**Snapshot:** mode `fingerprint`; rows `103`; flagged `is_pipeline_issue == True`
`29` (`runner_env_config`: 24, `module_resolution`: 4, `none`: 1); Jev
`labeled_at` max `2026-10-21T22:03:39.130056+00:00`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max
`2026-10-21T21:58:45.762116+00:00`; fingerprints `103`)

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL` on the trailing `test:zero-runtime`, `test:pigment-react`, `test:pigment-css-react` step | 2024-02-14 `d8558a579e` | 3 (402 runs) | `runner_env_config` | Root `test:coverage` ends with `&& pnpm test:<pkg>`, but only the `test:<pkg>:ci` variant exists at those commits. The step is the last element of the chain, so nothing follows it; the `nyc` + `mocha` run and the root LCOV complete first (median line coverage 90.4% versus 90.2% in neighbouring commits). The chained script runs the package's uninstrumented `test` (plain `mocha`), and those paths are `--exclude`d from the `mocha` glob: no mocha-era LCOV contains `pigment`/`zero-runtime` files and no run produced a nested LCOV. The chain only reaches the step when mocha passes fully; upstream removed the broken tail on 2024-04-23. | upstream defect |
| JSDOM computed-style assertions in `packages/mui-system/src/Grid/Grid.test.js` (20 assertion families plus `+ expected - actual`) | 2025-04-28 `b1c3344ad0` | 21 (124 runs) | `runner_env_config` | The era is bounded on both sides by upstream dependency bumps: the first failing run is `b1c3344ad0 Bump pnpm to 10.10.0 (#46020)` and the last is `2fffbbd308 Bump @types/react to ^19.1.6 (#46202)`. The immediately preceding run (pnpm@10.8.1) passes, all 124 pnpm@10.10.0 runs fail, and runs pass again from 2025-06-09 under pnpm@10.12.1 (`8239 passing`). The container used exactly the pinned `pnpm@10.10.0`. The assertion helper itself prints upstream's guidance: "Styles in JSDOM … skip the test in JSDOM e.g. `if (/jsdom/.test(window.navigator.userAgent)) this.skip();`". | upstream defect |
| `Error: Timeout of 20000ms … packages/mui-envinfo/envinfo.test.js` | 2024-01-04 `fd461cda5f` | 1 (94 runs) | `none` | The test spawns `npx --package <build> envinfo --json` and exceeded the 20 s per-test timeout. Upstream shortened it on the day the family ends: `93f307b735 [test] Speed up the envinfo test (#40669)` (2024-01-29). | upstream defect |
| `Cannot find module` on branch-intermediate refactors — `test/utils`, `./BasePopper`, `./useBadge`, `../composeClasses` | 2023-10-03 `3de335fd73`; 2024-07-26 `257b3bc528` | 4 (6 runs) | `module_resolution` | `test/utils` was a wrong import in `3de335fd73` (#39037), fixed by `9b1a06b39f` (#39291). `./BasePopper`, `./useBadge` and `../composeClasses` come from the single-parent branch intermediates `257b3bc528 remove files`, `2e6f73ca1c copy files` and `22ef52b059 restore files` of the `[core] Include history from the @mui/base components & hooks v2/v4` merge; the modules are restored in the merge head. | upstream defect |

## Conclusion

No Jev flag traces to the container, harness, or registry mirror: 0 confirmed
pipeline defects. All 29 flagged fingerprints — a union of 626 distinct runs —
attribute to commit-era upstream content: a broken non-CI coverage script, the
pnpm@10.10.0 dependency-tree era, a slow `envinfo` test fixed in #40669, and
branch-intermediate refactor commits. No work order for `install-and-run.sh` or
the `Dockerfile` follows from this audit.

## Label outcome

Remaining `acceptable`: 25 (`ERR_PNPM` 3, JSDOM computed style 21, envinfo timeout
1). Reclassified `reevaluated_acceptable`: 0 in this pass — the 4
`module_resolution` fingerprints already carried that label. Remaining
`problematic`: 0.

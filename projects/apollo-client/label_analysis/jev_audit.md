# Jev audit — apollo-client

**Source:** `label_analysis/failure_labels_jev_min.csv` (automated System 1 labels,
generated 2026-10-20), cross-checked against
`label_analysis/failure_labels_project_min.csv` and the project's git history.

The Jev snapshot evaluated 883 fingerprints. 359 carry `is_pipeline_issue == True`
(351 `runner_env_config`, 6 `none`, 2 `module_resolution`). All 359 originate from
four runs, and each is a genuine upstream defect at that commit rather than a
container or harness artifact:

| Run | Date | Flagged fingerprints | Finding |
|---|---|---|---|
| `278ba5fd223f` | 2021-11-03 | 348 | The jest `26→27` bump left `testEnvironment` unset, so the default `node` environment aborts every browser test with "The error below may be caused by using the wrong test environment". Upstream restored `testEnvironment: 'jsdom'` one day later in `745712847`. |
| `ba70b6254862` | 2024-11-07 | 7 | Merging `origin/main` into `release-3.12` deleted `src/testing/internal/profile/`, while the `release-3.12` hook tests still imported `createProfiler`/`profileHook`. Resolved in follow-up branch commits. |
| `7f0d459c7b3b` | 2021-11-16 | 2 | The `#8785` `useSyncExternalStore()` work requires `use-sync-external-store/shim`, whose package apollo-client declares as an optional peer dependency; npm 7+ skips optional peers, so the subpath was never installed. Upstream bumped the dependency on 2022-01-10. |
| `7bcde69848de` | 2024-12-04 | 2 | `@testing-library/react-render-stream@2.0.0-alpha.1` cannot create a React root inside the act environment forced by `@testing-library/react@16`, although the tests call `disableActEnvironment()`. |

**Conclusion:** no Jev flag traces to the container, the harness, or a registry
mirror. The affected fingerprints are labeled `acceptable` or
`reevaluated_acceptable` in `failure_labels_project_min.csv`, and no runner or
Dockerfile change is required.

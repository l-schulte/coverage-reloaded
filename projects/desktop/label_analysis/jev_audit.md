# Jev audit — desktop

**Source:** `label_analysis/failure_labels_jev_min_dedup.csv` (mode `dedup-keyword`: one row
per `(suite, keyword)` family).
**Snapshot:** Jev `labeled_at` max `2026-10-21T21:24:27`; rows `923`; flagged
`is_pipeline_issue == True` `789` (`runner_env_config` 689, `none` 98,
`module_resolution` 1, `node_runtime_syntax` 1); not flagged `134`. The file
predates the `family_fingerprints` column, so it records no covered-fingerprint
list; 922 of its 923 representative fingerprints exist in the rebuilt
1,765-fingerprint set.
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max
`2026-10-21T21:24:03`; fingerprints `1765`: 584 `acceptable`, 1,181
`reevaluated_acceptable`).

## Flagged families

| Family | Date / exemplar run | Rows | `env_subsystem` | Finding | Verdict |
|---|---|---|---|---|---|
| Temp-fixture cleanup `ENOENT` (`app/test/helpers/temp.ts` `rm()` retry loop) | 2025-03-27 `1743088545_f688751cbd` and `1743088576_d2a2b2719c` | 536 | `runner_env_config` | Upstream regression committed that day; the author fixed it 13 minutes later in `e45fa12eab` ("Don't retry more than once"). Both runs precede the fix. | upstream defect |
| `custom-ua` branch: `ReferenceError: __APP_VERSION__ is not defined` | 2023-06-28 `1687935475_e19beea34b` | 216 | `runner_env_config` | The branch's user-agent code reads `__APP_VERSION__`, which `app/test/globals.ts` did not define. Fixed on the same branch 31 minutes later in `c487f2177f` ("Fix __APP_VERSION__ in test env"). | upstream defect |
| `wip-log-parser`: git output parser returns no `sha` / `parentSHAs`, surfacing as "Unable to find commit for HEAD" and "Could not load commit" | 2020-12-08 `1607428119_a91fc7ed76` | 18 | `runner_env_config` | Mid-rewrite parser state on that branch; the author repaired it two minutes later in `180b3b57bd` ("Fix merge mistake"), and the second bad window on 2021-01-13 was fixed in `032101127f` ("math?"). | upstream defect |
| Trampoline refactor: `ReferenceError: trampoline_server_1 is not defined` | 2021-01-26 `1611680395_2151b42920` | 16 | `runner_env_config` | Circular import in the in-progress trampoline server pulled into `src/lib/git/environment.ts`; resolved across the follow-up branch commits ending in `2f96fc871f`. | upstream defect |
| `@github/alive-client` ESM entry: `SyntaxError: Unexpected token 'export'` | 2021-12-14 `1639497051_6dcf0e3292` | 1 | `node_runtime_syntax` | The 0.0.2 bump introduced an ESM-only entry point that jest could not transform; fixed on 2022-01-11 in `a721b10339` ("Make tests pass") by extending the jest transform configuration. The family spans ten runs up to that fix. | upstream defect |
| Electron `remote` mock: `ipcRenderer.sendSync is not a function` under `remote.getCurrentWindow()` | 2022-01-18 `1642564668_a2848ea9a4` | 1 | `runner_env_config` | The branch's test mock did not implement `sendSync` for the mocked remote module; the branch removed the `remote` dependency in `6a91da5f31` and `462a2084e2` the same night. | upstream defect |
| Git `file` transport blocked during submodule clone (`fatal: transport 'file' not allowed`) | 2022-10-18 `1666115323_2a2ad0fcf4` | 1 | `runner_env_config` | Commit "Update dugite to 2.1.0" pulled in a git that enforces the CVE-2022-39253 file-protocol restriction; the author reverted the setting 47 minutes later in `7cd667172c` ("Revert file transport setting"). | upstream defect |

Rows do not sum to distinct runs: one row is one `(suite, keyword)` family, so the
temp-fixture pair and the single-row families each cover several failing runs
through their `n_runs` value.

## Conclusion

No flagged fingerprint traces to the container, the harness, or a registry mirror.
All 789 flagged rows belong to eight commit-era upstream defects, each closed by a
follow-up upstream commit — most within minutes, the longest after three weeks. No
`install-and-run.sh` or Dockerfile change is required.

## Label outcome

The 789 flagged rows map to representatives whose human labels are 770
`reevaluated_acceptable` and 19 `acceptable`; there are no `problematic` and no
`unclear` fingerprints in the project. The 134 rows Jev did not flag are consistent
with that outcome and need no action.

One rule was narrowed during the label pass: `1e7778d6f7ca` matched the generic
`Timeout - Async callback was not invoked` body and would have shadowed the two
intentional `problematic` timeout rules (rebase progress, promisor remote). It now
matches only the `DesktopFileTransport` tests, so those timeout families still
surface for review.

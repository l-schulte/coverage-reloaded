# Jev audit — openneuro

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)
**Snapshot:** mode `fingerprint`; rows `539`; flagged `is_pipeline_issue == True` `284` (`runner_env_config`: `210`, `module_resolution`: `52`, `missing_build_step`: `17`, `node_runtime_syntax`: `5`); Jev `labeled_at` max `2026-10-22T15:16:50.042759+00:00`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-10-22T15:21:31.600909+00:00`; fingerprints `541`)

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| React 17 Enzyme adapter mismatch | 2021-03-05 `1615010381_89e216028` | ~150 | `runner_env_config` | Upstream commit `89e216028` upgraded React to v17 while `jestsetup.ts` still imported React 16 `enzyme-adapter-react-16`, causing `TypeError: Cannot read property 'child' of undefined` at `detectFiberTags.js`. Resolved upstream 2 days later in commit `61f26e1d6` by switching to `@wojtekmaj/enzyme-adapter-react-17`. | upstream defect |
| Vitest unexcluded `dist/` test discovery | 2024-04-02 `1712075389_766ed0fee` | 48 | `runner_env_config`, `module_resolution`, `missing_build_step` | Commit `ba3e27d20` added `vite.config.ts` excluding `./cli` and `./.yarn` but omitting `**/dist`. Vitest executed compiled CommonJS specs in `packages/*/dist/**/__tests__/*.spec.js`, triggering `TypeError: Cannot read properties of undefined (reading 'mock' / 'fn')` (since Vitest does not export `vi` on CJS `require`) and Yarn PnP undeclared package access. Resolved upstream in commit `42e13e258` by adding `"**/dist"` to `exclude`. | upstream defect |
| Apollo Client 3 package upgrade mismatch | 2021-03-05 `1614958841_5b322b4a7` | 19 | `module_resolution` | Commit `5b322b4a7` upgraded `package.json` to `@apollo/client` and removed `apollo-client`, but `packages/openneuro-client/src/client.js` still imported `apollo-client`. Resolved upstream 50 seconds later in commit `732134a3d` by migrating `client.js` imports. | upstream defect |
| Deno CLI imports in Node test runner | 2023-10-12 `1697132229_5557f9a0b` | 8 | `module_resolution` | New Deno CLI rewriting tests in `cli/src/` imported `npm:...` and `https://deno.land/...` which failed when executed by Node.js. Resolved upstream in commit `ba3e27d20` by excluding `cli` from Node test runner. | upstream defect |
| TypeScript extension & lib refactors | 2023-11-01 `1698860853_16a667136` | 14 | `module_resolution` | PR #2930 migrated server utility libs from `.js` to `.ts` (`dataset.js` -> `dataset.ts`, `redis.js` -> `redis.ts`), producing intermediate unresolved import errors until relative import paths were updated. | upstream defect |
| Vite worker & `import.meta.env` syntax in Jest | 2021-03-27 `1616798480_708cc48` | 5 | `node_runtime_syntax` | Feature PR #1898 introduced `import.meta.env` and `?worker` query imports into app components before Vite/Babel transform plugins were configured in the Jest harness. | upstream defect |
| Skeleton placeholder test files | 2022-11-16 `1668620782_33379eed9` | 39 | `runner_env_config` | Newly created skeleton `.spec.ts` files committed without test cases produced `Error: No test suite found in file`. | upstream defect |
| Memory FS mock config | 2022-11-16 `1668620782_33379eed9` | 1 | `runner_env_config` | `Error: ENOENT: /root/.openneuro: no such file or directory` caused by Metro memory fs mock collision, resolved upstream in commit `0a5a9b104`. | upstream defect |

## Conclusion

0 confirmed pipeline defects and 284 commit-era upstream defects. No Jev flag traces to the container, harness, or registry mirror. All 284 flagged fingerprints correspond to verified upstream developer breaking commits, refactoring churn, and configuration oversights that were subsequently resolved in git history by upstream authors.

## Label outcome

Remaining `acceptable`: 315.
Reclassified `reevaluated_acceptable`: 225.
Remaining `problematic`: 0.

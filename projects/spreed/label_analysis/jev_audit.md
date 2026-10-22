# Jev audit — spreed

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)  
**Snapshot:** mode `fingerprint`; rows `1504`; flagged `is_pipeline_issue == True` `218` (`module_resolution`: `182`, `runner_env_config`: `26`, `node_runtime_syntax`: `6`, `none`: `4`); Jev `labeled_at` max `2026-10-22T07:55:10.945460+00:00`  
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-10-22T08:17:37.536372+00:00`; fingerprints `1505`)

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|:---:|---|---|---|
| Vue Test Utils v2 / `createLocalVue` removal (`da873f9b7fc9`) | 2025-06-24 `6c9c670e0be5` | 145 | `module_resolution` | `TypeError: createLocalVue is not a function` during Vue 3 migration PR #12458; fixed in upstream commit `c683b89b32` (*"fix(vtu): migrate from createLocalVue to global plugins"*). | upstream defect |
| Missing component import paths (`f7b45d754f38`) | 2021-09-21 `68073a1de829` | 32 | `module_resolution` | `Cannot find module '@nextcloud/vue/dist/Components/Button'` in `Poll.vue` during PR #7465; fixed in upstream commit `d94236f83c` (*"Rename Button into ButtonVue"*). | upstream defect |
| Leaked Jest Date spy / broken `Date.now` (`605769ef8170`) | 2024-07-23 `78f40092f306` | 1 | `runner_env_config` | `TypeError: Date.now is not a function` caused by incomplete `jest.spyOn(global, 'Date')` mock; fixed in upstream commit `cd15420cbf` (*"fix(test): replace jest.spyOn with jest.useFakeTimers"*). | upstream defect |
| Missing `vue-material-design-icons` Jest transform (`f3df147df273`) | 2021-05-10 `fce24ef7ac58` | 2 | `runner_env_config` | `SyntaxError: Unexpected token '<'` when loading `.vue` icons from `node_modules`; fixed in upstream commit `5f51484396` (*"Fix jest config for icons and libs that need transpiling"*). | upstream defect |
| Missing `@nextcloud/vue` Jest transpilation (`(manual)`) | 2021-06-10 `deeeec37b652` | 2 | `node_runtime_syntax` | `Cannot use import statement outside a module` on `@nextcloud/vue`; fixed in upstream commit `18df7079c0` (*"Also transpile @nextcloud/vue in jest config"*). | upstream defect |
| Unmocked `initial-state` worker crash (`51279d9fe99a`) | 2021-10-29 `0ad342d12ff4` | 1 | `runner_env_config` | `Call retries were exceeded` from uncaught `loadState('spreed', 'federation_enabled')` in `conversationsService.spec.js`; fixed in upstream commit `a8fd7fc03b` (*"Fix JS unit tests"*). | upstream defect |
| Missing MediaRecorder mock (`(manual)`) | 2021-06-30 `63fe1ac0d71c` | 1 | `runner_env_config` | `TypeError: URL.createObjectURL is not a function` in `AudioRecorder.vue`; fixed in upstream commit `96b89c0f21` (*"Fix tests"*). | upstream defect |
| Message grouping DOM assertions (`a201bce7f066`) | 2025-01-30 `3fff20c3af8f` | 16 | `runner_env_config` | DOM child-count assertion failure in `MessagesList.vue`; upstream test bug resolved in PR updates. | upstream defect |
| Vitest migration transitional failures (`70d540829e16`) | 2025-08-25 `176c837c8e95` | 10 | mixed (`runner_env_config`, `module_resolution`, `node_runtime_syntax`, `none`) | Transitional spec errors (`TypeError: default is not a constructor`, event bus resolution) during vitest framework switchover; fixed in commit `d57b9d40fe` and follow-ups. | upstream defect |
| Miscellaneous isolated commit regressions (`58e6448997fa`, `58e6448997fr`, `3205baffb57f`, `(manual)`, `2b9c272a2a68`, `6057335f9174`, `71c5dbb604a7`, `a471a3a7e0c3`) | 2021-06 .. 2025-06 | 8 | mixed | Short-lived commit-era developer syntax, mock, or import errors fixed in upstream PR branches. | upstream defect |

## Conclusion

0 confirmed pipeline defects and 218 commit-era upstream defects.  
No Jev flag traces to the container, harness, or registry mirror.

## Label outcome

Remaining `acceptable`: 169. Reclassified `reevaluated_acceptable`: 49. Remaining `problematic`: 0.

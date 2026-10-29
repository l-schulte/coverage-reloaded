# Jev audit — n8n

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)
**Snapshot:** mode `fingerprint`; rows `1673`; flagged `is_pipeline_issue == True` `313` (`runner_env_config`: `262`, `ports_and_networking`: `28`, `node_runtime_syntax`: `12`, `module_resolution`: `6`, `none`: `2`, `missing_build_step`: `2`, `native_build_gyp`: `1`); Jev `labeled_at` max `2026-10-27T08:41:58.250830+00:00`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-10-27T07:33:18.737353+00:00`; fingerprints `1673`)

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| Vitest Worker RPC Timeouts & Tinypool RangeError | 2023-03-14 `1678796001_eb3ba83e632c29ab719512b6a5981ad12cdb6778` | 134 | runner_env_config | `turbo run test --concurrency=5` caused CPU starvation under container limits, triggering 10s `[birpc] timeout on calling "fetch"`. Mismatched min/max workers in `install-and-run.sh` triggered `RangeError` in Vitest 3.x. Fixed in `patch-coverage.js` and `install-and-run.sh`. | pipeline defect |
| Native `tree-sitter.node` GLIBCXX missing | 2025-10-31 `1761915490_9ae4e12ea721c56d6a6de796c6a7128746a5afa4` | 1 | native_build_gyp | Prebuilt `tree-sitter.node` in `editor-ui` requires `GLIBCXX_3.4.29`, missing from Debian Bullseye base. Fixed by pulling `libstdc++6` from Bookworm in `Dockerfile`. | pipeline defect |
| `json-schema-to-zod` missing barrel export extension | 2024-10-17 `1729169864_86a94b5523e4750fe188f8214d0050fcc4862041` | 1 | missing_build_step | Upstream fork typo `export from './json-schema-to-zod.js'` in `src/index.ts` failed under Jest. Fixed upstream by author Eugene in commit `28487edb13`. | upstream defect |
| `ai-workflow-builder.ee` missing Jest configuration | 2025-07-21 `1753089506_632b38119b7bb1bdf9d08a81b8060d799e7019e1` | 12 | node_runtime_syntax | Upstream deleted `jest.config.js` when renaming package in `632b38119b7b`, causing `SyntaxError: Unexpected token, expected "from"`. Fixed upstream 7 days later in commit `49a52a1150`. | upstream defect |
| CLI public API `Encryption key is missing or was not set` | 2023-03-15 `1678886649_b4e60c3b47e5a5e86c55ff737ae9a63e2c8836fc` | 16 | runner_env_config | Upstream omission in `workflows.controller.ee.test.ts` during CLI test refactor. Fixed upstream by author netroy in commit `6242cac53b`. | upstream defect |
| Core HTTP Proxy Tests `getaddrinfo ENOTFOUND api.example.com` | 2025-12-15 `1765808538_630fe3bfb94cfb68b37464da5477864f7a722bca` | 5 | ports_and_networking | Upstream regression in mock proxy resolution on Dec 15 2025, reverted upstream in `3acba8e541`. | upstream defect |
| Editor UI / Design System DOM & Snapshot Behavioral Tests | 2022-11-07 `1667832717_4483a30ffccca9f7da2f146a67a0a65675e47ee6` | 144 | runner_env_config / ports_and_networking / module_resolution / missing_build_step / none | Behavioral unit test assertions: `SettingsSourceControl.test.ts`, `useDebounce.test.ts`, `ExecutionsList.vue` null DOM refs, `Select.spec.ts` snapshots, unmocked `window.location.host` in `constants.ts`. | upstream defect |

## Conclusion

Out of 313 flagged fingerprints:
- **135 fingerprints** across 2 root-cause families represent **confirmed pipeline defects** (Vitest worker CPU starvation via excessive Turbo concurrency, and missing `GLIBCXX_3.4.29` runtime support for `tree-sitter`).
- **178 fingerprints** across 5 root-cause families represent **commit-era upstream defects and standard behavioral test failures**, confirmed via Git history and author follow-up commits.

Both pipeline defects have been addressed in `projects/n8n/Dockerfile`, `projects/n8n/patch-coverage.js`, and `projects/n8n/install-and-run.sh`.

## Label outcome

- Remaining `acceptable`: 120
- Reclassified `reevaluated_acceptable`: 58 (including the 12 `@n8n/ai-workflow-builder.ee` fingerprints reclassified from `acceptable`)
- Problematic resolved via work order / pipeline fix: 135 (covering 5,131 Vitest timeout commits and 1,653 tree-sitter GLIBC commits).

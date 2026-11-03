# Jev audit — opencrvs-core

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)
**Snapshot:** mode `fingerprint`; rows `4907` (append-only: covers all 4211 current
fingerprints plus 696 stale rows from earlier generations); flagged
`is_pipeline_issue == True` `421` (`runner_env_config`: 75,
`ports_and_networking`: 24, `module_resolution`: 25, `node_runtime_syntax`: 7,
`none`: 102) — of which **233 correspond to current fingerprints**; Jev
`labeled_at` max `2026-11-02T12:24:53Z`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at`
max `2026-11-02T11:57:27Z`; fingerprints `4211`; acceptable 3597,
reevaluated_acceptable 551, problematic 1, false_positive 62)

Current-set agreement: 3 937 human-acceptable ↔ Jev-acceptable; **233 Jev
"pipeline issue" fingerprints are human-acceptable/false-positive** (the
stateless-judge disagreements audited below); 1 human-`problematic` ↔
Jev-acceptable (the documented `updateFormDraftHandler` known gap — Jev agrees it
is not a pipeline defect).

> Note: 8 fingerprints initially failed to label (`Eden AI HTTP 400
> max_tokens_exceeded`) because the default 40-line context window swallowed a
> multi-KB JSON log line (a metrics request dump with a full JWT header).
> Re-run with `--context-above 2 --context-below 8` labeled all 8 as
> **acceptable** (0.65–0.85).

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | Union runs | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|---|
| **Missing local JWT key pair (`.secrets`)** — gateway key-loading suites die with `ENOENT: ... ../../.secrets/private-key.pem` | 2023-02 `1676305948_81b5a75f` | 8 (pre-fix; **0** in the current set) | 13 (all re-run) | `runner_env_config` | `.secrets/` is gitignored; the repo ships `dev:secrets:gen` (`package.json`, `setup.sh:342`) which our harness never ran. Fixed: `install-and-run.sh` now runs `dev:secrets:gen` when the script exists and the key pair is absent. Validated on `1676305948`: ENOENT gone, gateway **+473 covered lines (+18 %)**; all 13 runs re-run (12 recovered, 1 verified). | **pipeline defect — FIXED** |
| Search `ECONNREFUSED 127.0.0.1:9200` (`birthEventHandler`, `/populateHierarchicalLocationIds`) | 2022-01–2023-03 `1642099534_90b6f74e` | 8 (**47** at analysis time) | 13 (**63** at analysis time) | `ports_and_networking` | Tests mock the ES layer; neighbours pass; failure is flaky (re-run of `1642099534` passed with 0 failures, 48/50 tests green). Coverage effect measured: **+5 lines (0.03 pp)** — test-signal artifact only. 62 members archived and re-run (61 passed). No ES provisioning (repo pins `@elastic/elasticsearch@6.8.8` in that era). | **flaky — not a defect; labels stand** |
| hapi-sentry config cascade (`ValidationError: Invalid hapi-sentry options` + `Cannot read property 'server' of undefined`) | 2022-08-02 `2dcf669031c` | 110 (all in one run) | 1 | `ports_and_networking`, `none` | Upstream config bug; fixed in-repo **2 days later** by `dd9dd66a76` *"Checked SENTRY config variable exists before configure (#3700)"* (2022-08-04). | **upstream defect** |
| Auth `process.exit(1)` from `envalid cleanEnv` | 2024-11-14–22 `1731594330_1dee3407` | 2 | 11 | `runner_env_config` | Repo test helper `createProductionEnvironmentServer` sets `NODE_ENV: 'production'` but omits `COUNTRY_CONFIG_URL_INTERNAL` (schema has only `devDefault`, ignored in production). Introduced by `83f8172c90` (2024-10-01); branch fix `536e0afbb3` (2024-11-25); present on mainline by 2025-02. | **upstream defect** |
| Phone-fixture window — `Cannot destructure property 'pattern'/'start'/'num' of window.config.PHONE_NUMBER_PATTERN / NID_NUMBER_PATTERN` | 2021-08–2022-01 `1638510738_9b2d0b29` | 11 | 245 | `node_runtime_syntax` | Phone-validation refactor `89b633f270` (2021-07-29) without updating the test config fixture; fixed by `5658062d18` *"Unit test fixes (#2485)"* (2022-01-27). | **upstream defect** |
| `TypeError: name.replaceAll is not a function` | 2021-12–2022-02 `1638510738_9b2d0b29` | 8 | 69 | `node_runtime_syntax` | Repo's own source (`Avatar*.tsx`) uses `replaceAll` (Node ≥15) while the repo's Dockerfile pins `FROM node:erbium` (=12). Our Node selection matches the repo's declared runtime. | **upstream defect** |
| `Tablet tests › redirects to detail page` — `expect(received).toContain("/details/<uuid>")` | 2021-12 `1638510738_9b2d0b29` | 1 | 142 | `node_runtime_syntax` | Plain URL-substring assertion mismatch; no infra signature. | **upstream defect** |
| `Configuration error: Could not locate module @client/forms/configuration/queries` | 2022-04 `1650016839_6f080415` | 2 | 18 | `module_resolution` | The file lives at `src/forms/configuration/formDrafts/queries.ts`; the test imports the path **without the `formDrafts/` segment** at those commits. | **upstream defect** |
| formDraft reducer / missing-default churn (`Actions may not have an undefined "type"`, `Default birth formDraft not found`) | 2022-04/05 `1650273250_bd3284c3` | 8 | 16 | `module_resolution` | Refactor window: `aae6c83733` *"Merged formDrafts reducer into formConfig reducer"* (2022-05-02), `a7c953e51d` *"Handled formDrafts if there is none saved yet"* (2022-05-09). | **upstream defect** |
| vitest `⎯⎯ Unhandled Errors ⎯⎯` summaries (generic trigger line, no cause) | various | 27 | 805 | mixed | Generic summary lines; the underlying errors belong to the families above. | **generic noise — human `false_positive` correct** |
| Residual assorted fingerprints (client UI-wait/selector, `mockingoose`, one-off assertions) | various | 63 | 341 | mixed / `none` | No shared infra signature; commit-era test churn. | **upstream defect — human labels correct** |

## Conclusion

**One confirmed pipeline defect** — the missing gitignored `.secrets` JWT key pair
(8 fingerprints, 13 runs, Feb 2023). It has been fixed in `install-and-run.sh`
(era-gated `dev:secrets:gen`) and validated end-to-end: gateway suites load again
and the commit gains **+473 covered lines (+18 %)**. All 13 affected runs were
re-run.

**No other Jev flag traces to the container, harness, registry mirror, or test
runner.** Counts below are as of the current fingerprint set (4 211 fps, Jev
labels 2026-11-02T12:24Z); families may overlap, so they sum to slightly more
than the 233 unique flagged fingerprints. The remaining 233 current-set flags
decompose into: one verified *flaky* family (search ES connections — 8 fp /
13 runs; coverage effect +5 lines), and otherwise commit-era upstream defects
that the repository fixed itself days-to-weeks later (hapi-sentry cascade
110 fp / 1 run; phone-fixture window 11 fp / 245 runs; `replaceAll` on the
pinned Node 12, 8 fp / 69 runs; the Tablet URL assertion 1 fp / 142 runs;
formDraft refactor churn 8 fp / 16 runs; the wrong `@client/…/queries` import
2 fp / 18 runs; auth production-env helper 2 fp / 11 runs) or generic
error-summary lines a stateless judge cannot attribute (27 fp / 805 runs) plus a
63 fp / 341-run residual of assorted dev-era fingerprints. The `.secrets`
fingerprints themselves are absent from the current set — they disappeared once
the fix and the 13 re-runs landed.

## Label outcome

- Remaining `acceptable`: **3597**
- Reclassified `reevaluated_acceptable`: **551**
- Remaining `problematic`: **1** — `701263588408`
  (`updateFormDraftHandler handler › should update question using mongoose`,
  5 s jest timeout at `1648707415`, Apr 2022). Documented known gap: reproduces
  **4/4** re-runs including one on an almost idle host (load ≈ 6/256 cores), i.e.
  deterministic at that commit (11.4 s suite vs the 5 s async budget); coverage
  remains valid (soft failure).
- `false_positive`: 62
- No label changes were applied as a result of this audit: the human labels were
  already correct in every disagreement, and the one real pipeline defect is
  addressed in the harness rather than by relabeling its fingerprints.

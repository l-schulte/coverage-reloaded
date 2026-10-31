# gatsby — failure-family assessment

Static re-assessment of the `unclear` fingerprints produced by `check_failures_v2.py`
(window `min`). Labels and `auto_classify` rules live in `failure_patterns.json` and
`failure_labels_project_min.csv`; this file records the reasoning and the evidence so it
is not lost when labels are regenerated.

Scope at the start of the pass: 683 fingerprints, 100 % labeled, 43 `unclear`, 0 `problematic`.
Scope after the re-runs started (388 runs archived for `fix_lmdb_datastore_flag`):
676 fingerprints, 33 `unclear`.

## Verdicts

| family | fingerprints | union runs | span | verdict |
|---|---|---|---|---|
| `Query schema … GC happen mid running` | 5 | 388 | 2022-06-30 .. 2022-10-18 | **problematic** (fixed) |
| `distinct field › returns distinct values on scalar field with resolver` | 1 | 21 | 2022-12-07 .. 2022-12-13 | `reevaluated_acceptable` |
| Parcel `compile-gatsby-files` per-test timeout | 4 | 35 | 2022-10-19 .. 2024-01-03 | `reevaluated_acceptable` |
| `//.cache/schema.gql` ENOENT (v4 pre-major window) | 33 | 3 | 2021-09-14 | `reevaluated_acceptable` |

---

## 1. Query schema pagination GC (5 fingerprints / 388 runs) — problematic, fixed

```
● Query schema › on pagination fields › group field › works correctly if GC happen mid running
expect(received).toBeUndefined()
Received: [[GraphQLError: Test setup is broken, something is keeping a node in memory]]
```

The test creates a `WeakRef` to a node, calls `clearKeptObjects()` + `gc()` and aborts if the
reference survives. In this era `packages/gatsby/src/datastore/datastore.ts` selected the store
as follows:

```js
let isLmdb = isLmdbStoreFlagSet()   // process.env.GATSBY_EXPERIMENTAL_LMDB_STORE
...
dataStore = setupInMemoryStore()    // when the env var is unset
```

Upstream CI exported `GATSBY_EXPERIMENTAL_LMDB_STORE: 1` (`.circleci/config.yml`); the pipeline
did not. The in-memory store holds nodes strongly, so the `WeakRef` could never clear.

Controlled check: the same test file, unchanged, passes on every run after `dc82d92e`
(2022-10-18, "Remove LOCKED_IN feature flags", datastore becomes LMDB unconditionally) with the
same `lmdb` version, and fails on all 388 commits before it.

Fix: `install-and-run.sh` exports `GATSBY_EXPERIMENTAL_LMDB_STORE=1` when the checked-out commit
still contains the `GC happen mid running` test. Runs archived to `archive/fix_lmdb_datastore_flag/`.
Rule `80d01d08df77` keeps `problematic` so a regression resurfaces.

## 2. Distinct resolver over date fields (1 fingerprint / 21 runs) — reevaluated_acceptable

```
● Query schema › on pagination fields › distinct field › returns distinct values on scalar field with resolver
expect(received).toBeUndefined()
Received: [[GraphQLError: String cannot represent value: {}]]
```

A one-week upstream dependency regression, not a GC or pipeline problem:

| boundary | commit |
|---|---|
| first failing run | `fecf779471` — *update dependency lmdb to v2.7.1 (#37160)*, 2022-12-07 |
| last failing run | `20fe839d80` — 2022-12-13 |
| fix | `9f6f6b8a26` — *Revert "update dependency lmdb to v2.7.1 (#37160)" (#37255)*, 2022-12-14 |

`lmdb` 2.7.1 mishandled `Date`-valued fields, so `distinct` returned `{}`. All 21 commits in the
window fail and the failure disappears with the revert.

## 3. Parcel `compile-gatsby-files` per-test timeout (4 fingerprints / 35 runs) — reevaluated_acceptable

```
● misnamed gatsby-node files › should panic on gatsby-node.jsx
thrown: "Exceeded timeout of 15000 ms for a test.
```

`compile-gatsby-files.ts` sets `jest.setTimeout(15000)`, which overrides the CLI
`--testTimeout=30000`; a full Parcel compile of a fixture project occasionally exceeds 15 s in the
2-CPU container (35 of 1,292 commits in the era, 2.7 %). Upstream hit the same limit and raised the
same value to 60 s in `0a80cd6d61` (2024-01-09); the last observed failure is 2024-01-03.

### Coverage impact: none measurable

A jest per-test timeout fails that one test and lets the run continue; coverage is written at the
end of the process, and the fixtures the timed-out test would have compiled are exercised by
sibling tests in the same file. Measured against the immediate neighbouring commits:

| timed-out run | prev | this | next |
|---|---|---|---|
| `1666161629_e574964a` | 16,800/31,523 = 53.29 % | 16,801/31,525 = 53.29 % | 16,802/31,525 = 53.30 % |
| `1680736435_fd168e0e` | 16,933/32,059 = 52.82 % | 16,997/32,109 = 52.94 % | (neighbour is a hard error) |
| `1704281793_6cb6ffb0` | 17,425/33,133 = 52.59 % | 17,424/33,133 = 52.59 % | 17,425/33,133 = 52.59 % |

Largest deviation: 1 line of ~31,500 (0.003 %); one case is *higher* than its predecessor.
Per-file checks on the first run: `compile-gatsby-files.ts` 51/76 lines in all three runs, and the
compiled fixtures 54/290 lines in all three runs. Re-running therefore cannot change coverage — it
would only flip `exit_code` to 0. Rule `dbcc1caa7eaa` → `reevaluated_acceptable`.

## 4. `//.cache/schema.gql` ENOENT (33 fingerprints / 3 runs) — reevaluated_acceptable

```
● dateResolver › should return "Jan 29, 2018": 2018-01-29T00:00:00.000Z
ENOENT: no such file or directory, open '//.cache/schema.gql'
```

All 33 fingerprints are the same failure: the v4 pre-major bump left an unconditional
`shouldGenerateEngines()` stub writing to `//.cache/schema.gql` (empty `program.directory`), so every
schema-dependent test aborted. The 33 is fingerprint inflation — the failing test-name line is
identical and only the printed snapshot value on the following lines varies.

| time (2021-09-14) | commit |
|---|---|
| 09:43 / 09:48 / 12:00 | failing runs `f8c5141bf7`, `00a968257c`, `2b06d36b00` |
| 14:34 | `b622b22e3a` — *implement shouldGenerateEngines (#33175)* |
| 18:03 | `4712acc619` — *adjust tests after the bump (#33171)* |

Upstream's own branch was broken for ~2.5 hours; the next commits pass. Rule `6c2fbfce4682` →
`reevaluated_acceptable` (its pattern is already specific to `'//\.cache/schema\.gql'`).

## 5. `makeSourceFromOperation › testing prioritize: true, type: products` — 1 run, problematic

```
thrown: Object { "context": { "sourceMessage": "Could not source from bulk operation" },
  "error": [FetchError: request to https://my-shop.shopify.com/admin/api/2021-07/graphql.json
            failed, reason: getaddrinfo EAI_AGAIN my-shop.shopify.com] }
```

`packages/gatsby-source-shopify/__tests__/source-from-operation.ts` registers `graphql.query` /
`graphql.mutation` MSW handlers, so the request should never reach the network. In this single run
(`1670012200_dd52a14fbe`) the handlers did not intercept and the request escaped to a placeholder
host whose DNS lookup failed. The same suite passes in the surrounding runs, so this is a one-off
interception/DNS race rather than a reproducible defect.

Verdict: `problematic`. The run was archived to
`archive/shopify_msw_interception_escape/` for re-run. No `auto_classify` rule was created: the only
distinguishing text sits five lines into the body (`sourceMessage: "Could not source from bulk
operation"`), beyond the 3-line `min` window, so any rule would reduce to the generic
`thrown: Object {` and would swallow unrelated failures. If the failure recurs it returns as a new
fingerprint and should be re-assessed against this note.

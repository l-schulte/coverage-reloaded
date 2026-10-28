---
name: jev-failure-analysis
description: Analyze, audit, and triage failure classifications from the Jev automated labeler (failure_labels_jev_min.csv via check_failures_jev_v2.py). Cross-references Jev's independent decisions against git history and human labels to differentiate true pipeline bugs from commit-era regressions, writes the audit artifact `projects/<p>/label_analysis/jev_audit.md`, and translates confirmed pipeline issues into actionable runner/Dockerfile fixes.
license: MIT
metadata:
  audience: developers
  workflow: failure-analysis
---

## What I do

I analyze the output of the automated System 1 labeler ([`check_failures_jev_v2.py`](../../check_failures_jev_v2.py)) stored in `projects/<p>/label_analysis/failure_labels_jev_min.csv`.

Jev evaluates failures statelessly as an uncorrupted second opinion. My job in a new session is to:
1. **Audit Jev's `problematic` verdicts** against the project's git history to perform **causal attribution** (differentiating our pipeline bugs from commit-era developer mistakes).
2. **Cross-reference discrepancies** between Jev's verdicts and human labels in `projects/<p>/label_analysis/failure_labels_project_min.csv`.
3. **Synthesize confirmed pipeline failures into actionable work orders** for `install-and-run.sh` or the `Dockerfile` to recover commits toward the $\ge 90\%$ coverage inclusion criterion.
4. **Record the audit** in `projects/<p>/label_analysis/jev_audit.md` so the result is reviewable without re-reading logs, and so `maintain-project-overviews` can cite it.

---

## Core Context & Files

- **Input label file (fingerprint mode):** `projects/<p>/label_analysis/failure_labels_jev_min.csv` (`--window max` writes `failure_labels_jev_max.csv`). One row per `fp_min`/`fp_max` fingerprint, so the row count is directly comparable with the human label CSV.
- **Input label file (dedup-keyword mode):** `projects/<p>/label_analysis/failure_labels_jev_min_dedup.csv` (max: `failure_labels_jev_max_dedup.csv`). One row per `(suite, normalized keyword)` family; the row's `fingerprint` is the family representative. Membership is not stored in the file; it is reconstructed from the human CSV with the same grouping when needed (`--report` does this). **Row counts are not comparable with the human CSV** — one dedup row covers one or more fingerprints.
  - Columns (both modes): `project, window, run_id, suite, exit_code, line_number, fingerprint, n_runs, keyword, is_pipeline_issue, confidence, env_subsystem, labeled_at`
- **Reference human labels:** `projects/<p>/label_analysis/failure_labels_project_min.csv` — join on `fingerprint`.
- **Family cards:** `projects/<p>/label_analysis/<p>_min.jsonl` (from `check_failures_v2.py <p> --window min --analyze`) — the same families as above, with `block`, `n_variants`, `suites`, `first_run`/`last_run`.
- **Execution script:** `check_failures_jev_v2.py` in the workspace root (implementation: `failure_triage/jev.py`).
  - Flags: `--project <p>`, `--window min|max`, `--limit <N>`, `--report`, `--dry-run`, `--all`, `--suite`, `--dedup-keyword`, `--concurrency`, `--provider {auto,edenai,typesafe}`, `--model typesafe/jev-latest`, `--yes`, `--self-test`.
  - Routes either through Eden AI (`EDENAI_API_KEY` from `.env`, endpoint `POST /v3/alpha/decisions`, model `typesafe/jev-latest`) or direct TypeSafe (`TYPESAFE_API_KEY`).
  - Reuses the v2 fingerprints and SQLite sidecar (`projects/<p>/label_analysis/failure_labels_v2.db`), **never writes the human label CSVs**, and prints the number of items before spending API tokens. `--dry-run` never calls the API; `--yes` skips the confirmation (use only when the count is already known).
- **Run logs:** `projects/<p>/logs/<run_id>.log` (where `run_id = <timestamp>_<commit_hash>`).
- **Audit output (written by this skill):** `projects/<p>/label_analysis/jev_audit.md`. This is the durable record of the audit and the evidence behind the "complete JEV test failure check" checklist item. The per-project `OVERVIEW.md` links to it; the overview never restates the audit.
- **Project overviews:** `projects/<p>/OVERVIEW.md` (links to the audit and the label CSVs; it does not carry the Jev findings themselves).

Retired v1 artifacts (`failure_labels_jev.csv`, `failure_labels_project.csv`) may still sit at the project root or under `label_analysis/v1/`. They are reference only; disclose them in-session if they influence anything, and never treat them as the current Jev output.

### ⚠️ Understanding Deduplication & the `run_id` Column (Exemplar vs. Real Blast Radius)

- Both Jev and human CSVs are deduped by `fingerprint` (v2: `fp_min` by default, `fp_max` with `--window max`).
- **Each row is a unique fingerprint, not a single run:** one row covers every run that produced that error block.
- **`--dedup-keyword` is a different axis.** It groups fingerprints by `(suite, normalized keyword)` and sends one representative per family to the provider. It writes the separate `_dedup.csv` artifact, whose rows are families, not fingerprints. A dedup file naturally has fewer rows than the human CSV; this is not missing coverage. Never compare row counts across modes. Family membership is recovered from the human CSV with the same grouping when it is needed.
- **`run_id` is merely the exemplar:** the earliest chronological run where the fingerprint appeared. It does NOT mean the failure was confined to that run.
- **`n_runs` and the DB union indicate the real blast radius:** the CSV `n_runs` column is per fingerprint; `--report` prints a proper union (`COUNT(DISTINCT run_id)` over the group's fingerprints) from the SQLite sidecar. Without the DB it falls back to a sum and warns — never present that fallback as a run count.
- **Never report exemplar counts as run counts.** Always distinguish:
  1. **unique fingerprints** (`len(rows)`),
  2. **detections** (rows in `failures`),
  3. **distinct runs affected** (union).

---

## The Causal Attribution Principle (Upstream Regression vs. Pipeline Defect)

Jev is an expert anomaly detector for environment, runtime, and configuration defects, but it evaluates log snippets **statelessly without git history**.

When Jev flags `is_pipeline_issue = True`:
* **Hypothesis A: Replay Pipeline Defect (Study-Problematic)**
  - *Cause:* Our container or runner failed to supply an OS package, network bypass, Node flag, or build step.
  - *Symptom in Git:* The failure persists across many commits or entire eras; upstream developers never committed broken code.
  - *Action:* **Fix `install-and-run.sh` or `Dockerfile`.**
* **Hypothesis B: Commit-Era Developer Mistake (Study-Acceptable)**
  - *Cause:* Upstream developers committed broken configurations (e.g. bumping Jest to v27 without setting `testEnvironment: "jsdom"`, committing syntax errors, or forgetting local files).
  - *Symptom in Git:* The upstream author noticed the failure on their CI and pushed a fix commit 15–60 minutes later.
  - *Action:* **Keep as `reevaluated_acceptable`. Do not alter the pipeline.**

---

## Canonical Problematic Subsystems & Fix Archetypes

When Jev identifies a confirmed pipeline defect, map it to one of these proven project archetypes (the `env_subsystem` column carries Jev's grouping):

| Subsystem | Typical Failure Signature | Historical Precedent & Fix |
|---|---|---|
| `native_build_gyp` | `gyp ERR!`, missing Python 2.7, `GLIBC_X.XX not found`, missing headers | `flowfuse`: Conditional `npm_config_build_from_source=true npm rebuild sqlite3`. `vega-lite`: `libjpeg-dev`, `libgif-dev` in Dockerfile. |
| `missing_build_step` | Missing Playwright browser, missing `dist/`, missing submodules (`ENOLOCAL`) | `material-ui`: Export `TEST_SCOPE=node`. `flowfuse`: Run `git submodule update --init`. `rxdb`: Run `npm run build:plugins` before test. |
| `node_runtime_syntax` | Ambiguous ESM/CJS parsing, `ERR_REQUIRE_CYCLE_MODULE`, SyntaxError | `material-ui`: Export `--no-experimental-detect-module`. `rxdb`: Export `--no-experimental-require-module`. |
| `ports_and_networking` | `EADDRINUSE :::3000`, `ECONNREFUSED`, sandbox DNS timeouts | `flowfuse`: Inject dynamic `$PORT`. `vega-lite`: `PUPPETEER_SKIP_DOWNLOAD=true`. `rxdb`: Pre-pin S3 DNS via `resolve-and-pin.sh`. |
| `memory_exhaustion` | JavaScript heap out of memory, SIGKILL, process exit 134 | `rxdb`: Export `NODE_OPTIONS="--max-old-space-size=8192"`. `uwazi`: Increase `container_cpus` in `config.json`. |
| `runner_env_config` | SQLite in-memory isolation, testTimeout ignored by runner | `flowfuse`: Inject `pool-shim.js` to isolate SQLite `:memory:` connections. `uwazi`: Inject `jest.setTimeout(60000)` into Jest setup. |

---

## Output artifact — `label_analysis/jev_audit.md`

Write this file at the end of the audit (Phase 3). It is the durable evidence for
the "complete JEV test failure check" checklist item in
`projects/<p>/OVERVIEW.md`; the overview links to it and never restates it.

Rules:

- Record the mode and both snapshots: `dedup_keyword` (fingerprint vs
  dedup-keyword), the Jev file path, its `labeled_at` maximum, row count, and
  flagged count; plus the human label CSV (`labeled_at` maximum, fingerprint
  count). Do not claim a covered-fingerprint count from the dedup file; if it is
  needed, compute it from the human CSV with the same grouping.
- Before auditing, compare the recorded snapshots with the current files. In
  fingerprint mode the Jev row count should equal the human fingerprint count; in
  dedup mode the row count is lower by design and a row-count difference is not
  staleness. A changed `labeled_at` or human fingerprint count means the snapshot
  is stale: regenerate the Jev file with `check_failures_jev_v2.py` (ask first —
  it spends API tokens) and audit the fresh file.
- Cover every flagged fingerprint, grouped by root-cause family. State the
  verdict (`upstream defect`, `pipeline defect`, `unclear`) and the evidence
  (commit hashes, follow-up fix commit, log signature).
- Record the label outcome: which fingerprints remain `acceptable`, which were
  reclassified `reevaluated_acceptable`, and which stay `problematic` with a work
  order.
- When there are zero flagged fingerprints, still write the file with the
  snapshot metadata and `No flagged fingerprints.`
- Re-write the file whenever the Jev CSV changes (new `labeled_at`, row count, or
  flagged count). An audit whose snapshot metadata no longer matches the CSV is
  outdated and does not satisfy the checklist.
- When no Jev CSV exists, do not write the file; report `n/a (no Jev file)`.

Template:

```markdown
# Jev audit — <project>

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode) or
`label_analysis/failure_labels_jev_min_dedup.csv` (dedup-keyword mode)
**Snapshot:** mode `<fingerprint / dedup-keyword>`; rows `<n>`; flagged
`is_pipeline_issue == True` `<n>` (`<env_subsystem>`: `<n>`, ...); Jev
`labeled_at` max `<ISO>`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max
`<ISO>`; fingerprints `<n>`)

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| <root cause> | <date> `<hash>` | <n> | <subsystem> | <commit / follow-up fix / log signature> | <upstream defect / pipeline defect / unclear> |

## Conclusion

<Number of confirmed pipeline defects and number of commit-era upstream defects.
If zero: no Jev flag traces to the container, harness, or registry mirror.>

## Label outcome

<Remaining `acceptable`: <n>. Reclassified `reevaluated_acceptable`: <n>.
Remaining `problematic`: <n> (link the work order).>
```

## Phased Triage Protocol

Follow this structured protocol when asked to analyze Jev's output.

> [!IMPORTANT]
> **Always talk to the user first after Phase 1.** Never dive head-first into investigating an unknown number of issues or individual logs without presenting the cluster overview and getting user confirmation on which issues to prioritize.

### Phase 1 — Summary, Discrepancy Matrix & Cluster Overview
Bounded scope: compile high-level statistics and cluster disagreements; do NOT inspect individual logs or commit diffs yet.

1. **Aggregate stats:** run `python3 check_failures_jev_v2.py --project <p> --report` (prints the mode, rows, covered fingerprints, union runs overall, and a per-`env_subsystem` table). Add `--dedup-keyword` to report the `_dedup.csv` artifact when that mode was used. If no Jev CSV exists yet, say so and ask before running without `--report` — that spends API tokens.
2. **Discrepancy matrix:** join `failure_labels_jev_min.csv` with human labels in `failure_labels_project_min.csv` on `fingerprint`:
   - Agreement: (acceptable, acceptable), (reevaluated_acceptable, acceptable), (false_positive, …).
   - Discrepancy: Jev `acceptable` vs human `problematic`, Jev `problematic` vs human `acceptable`/`reevaluated_acceptable`, or any other mismatch. Rows missing on one side are "Jev unlabeled" / "human unlabeled", not disagreements.
3. **Cluster grouping:** group all problematic verdicts (`is_pipeline_issue == True`) and discrepancies into distinct families by underlying subsystem/pattern (the JSONL `block`/`keyword` are the grouping source). For each family report both:
   - the **unique fingerprints** (deduped rows),
   - the **actual distinct runs affected** (union from `--report` / the SQLite sidecar — never a sum of `n_runs`).
4. **Present findings:**
   - fingerprints evaluated vs distinct runs affected;
   - agreement vs disagreement matrix between Jev and human labels;
   - distinct clusters table: `Family / Fingerprint | env_subsystem | Exemplar Run | Fingerprints | Union Runs | Human Label vs Jev Verdict (confidence)`.

**Checkpoint 1 (Mandatory Stop Point):**
Present the summary table and discrepancy clusters. Ask the user:
> *"Here is the summary of discrepancies and failure clusters between Jev and the human labels (including affected runs). Which cluster(s) would you like to investigate first, and in what order?"*
**STOP and wait for the user's response before proceeding to Phase 2.**

---

### Phase 2 — Targeted Causal Trace (Selected Clusters Only)
Bounded scope: investigate only the specific clusters or runs selected by the user.

For each selected cluster:
1. **Extract log context:** open `projects/<p>/logs/<run_id>.log` around the reported `line_number` to inspect the exact stack trace and error message (or read the `block` on the family card).
2. **Inspect the commit:** run `git -C projects/<p>/repo show <hash> --stat` to see what changed in that commit.
3. **Check immediate follow-up commits:** run `git -C projects/<p>/repo log --oneline <hash>..HEAD | head -n 5`.
   - Did the author push a fix commit immediately after (e.g., *"Fix tests after updating X"*)?
   - If yes: document as **`reevaluated_acceptable`** (author bug).
   - If no: verify whether our container environment is missing a dependency or configuration.
4. **Cluster validity:** if a Jev `problematic` cluster turns out to span several distinct root causes, split it — one `env_subsystem` row can hide an over-broad classification.

**Checkpoint 2:**
Present the causal attribution findings for the investigated cluster(s). Ask:
> *"Should we adjust any labels for this cluster, dive into another cluster, or proceed to work orders?"*
Wait for user input before moving forward.

---

### Phase 3 — Actionable Work Order Formulation & Label Adjustments
For confirmed pipeline defects or agreed-upon label updates:
1. **Label adjustments:** Jev labels and human labels are separate artifacts; propose the exact change and apply it only on the user's approval — human labels go through `check_failures_v2.py` (interactive keys / `--review`), Jev labels are regenerated with `check_failures_jev_v2.py`. Then **write or refresh `label_analysis/jev_audit.md`** with the snapshot metadata and findings (template above). The per-project `OVERVIEW.md` links to that file; do not paste the findings into the overview.
2. **Work orders:** for confirmed pipeline defects, formulate a minimal, commit-era-aware recommendation for `install-and-run.sh` or `Dockerfile`.
   - Follow `AGENTS.md §6`: never apply unconditional global changes that risk breaking working historical eras; branch conditionally on package manager, detected files at checkout, or Node engine versions.
3. Output the prioritized fix order based on the number of commits recovered (union runs), never a summed occurrence count.

**Off-limits** (same as the `labeled-failure-analysis` skill): static analysis only — no container launches, no edits to `install-and-run.sh`, `Dockerfile`, `failure_patterns.json`, or shared scripts without explicit permission; the only file this skill writes is `label_analysis/jev_audit.md` (label CSVs are changed through the tools above). Lead with a 3-sentence summary and one concrete verification step.

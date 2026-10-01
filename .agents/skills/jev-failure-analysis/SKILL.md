---
name: jev-failure-analysis
description: Analyze, audit, and triage failure classifications from the Jev automated labeler (failure_labels_jev.csv). Cross-references Jev's independent decisions against git history, human labels, and project OVERVIEW.md to differentiate true pipeline bugs from commit-era regressions, then translates confirmed pipeline issues into actionable runner/Dockerfile fixes.
license: MIT
metadata:
  audience: developers
  workflow: failure-analysis
---

## What I do

I analyze the output of the automated System 1 labeler ([`check_failures_jev.py`](../../check_failures_jev.py)) stored in `projects/<project>/failure_labels_jev.csv`. 

Jev evaluates failures statelessly as an uncorrupted second opinion. My job in a new session is to:
1. **Audit Jev's `problematic` verdicts** against the project's git history to perform **causal attribution** (differentiating our pipeline bugs from commit-era developer mistakes).
2. **Cross-reference discrepancies** between Jev's verdicts and human labels in `failure_labels_project.csv`.
3. **Synthesize confirmed pipeline failures into actionable work orders** for `install-and-run.sh` or the `Dockerfile` to recover commits toward the $\ge 90\%$ coverage inclusion criterion.

---

## Core Context & Files

- **Input Label File:** `projects/<project>/failure_labels_jev.csv`
  - Columns: `project, run_id, suite, exit_code, line_number, fingerprint, occurrences, keyword, is_pipeline_issue, confidence, env_subsystem, labeled_at`
- **Reference Human Labels:** `projects/<project>/failure_labels_project.csv`
- **Execution Script:** `check_failures_jev.py` in the workspace root.
  - Supports `--project <p>`, `--limit <N>`, `--report`, `--dedup project`, and `--self-test`.
  - Routes either through Eden AI (`EDENAI_API_KEY` from `.env`, endpoint `POST /v3/alpha/decisions`, model `typesafe/jev-latest`) or direct TypeSafe (`TYPESAFE_API_KEY`).
- **Run Logs:** `projects/<project>/logs/<run_id>.log` (where `run_id = <timestamp>_<commit_hash>`).
- **Project Overviews:** `projects/<project>/OVERVIEW.md` (documents known failures and historical setup fixes).

### ⚠️ Understanding Deduplication & the `run_id` Column (Exemplar vs. Real Blast Radius)

- `check_failures_jev.py` operates with `--dedup project` by default.
- **Each row is a unique signature, not a single run:** Each row in `failure_labels_jev.csv` and `failure_labels_project.csv` represents a deduplicated failure fingerprint (trigger line, suite, normalized error).
- **`run_id` is merely the exemplar:** The `run_id` column stores only the **earliest chronological run** where that fingerprint was first observed. It does NOT mean the failure was confined to that single run!
- **`occurrences` indicates the real blast radius:** The `occurrences` column records how many distinct runs experienced that failure signature across the repository's history.
- **Never report exemplar counts as run counts:** Grouping the CSV rows by `run_id` only tells you the earliest commits where new failure signatures were introduced. A cluster with 1 exemplar `run_id` might actually affect 50 subsequent commit runs! When presenting summaries, always distinguish between:
  1. **Unique failure signatures** (number of deduplicated rows/fingerprints),
  2. **Total failure occurrences** (sum of `occurrences`),
  3. **Total distinct runs affected** (the set of unique run directories experiencing the failures).

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

When Jev identifies a confirmed pipeline defect, map it to one of these proven project archetypes:

| Subsystem | Typical Failure Signature | Historical Precedent & Fix |
|---|---|---|
| `native_build_gyp` | `gyp ERR!`, missing Python 2.7, `GLIBC_X.XX not found`, missing headers | `flowfuse`: Conditional `npm_config_build_from_source=true npm rebuild sqlite3`. `vega-lite`: `libjpeg-dev`, `libgif-dev` in Dockerfile. |
| `missing_build_step` | Missing Playwright browser, missing `dist/`, missing submodules (`ENOLOCAL`) | `material-ui`: Export `TEST_SCOPE=node`. `flowfuse`: Run `git submodule update --init`. `rxdb`: Run `npm run build:plugins` before test. |
| `node_runtime_syntax` | Ambiguous ESM/CJS parsing, `ERR_REQUIRE_CYCLE_MODULE`, SyntaxError | `material-ui`: Export `--no-experimental-detect-module`. `rxdb`: Export `--no-experimental-require-module`. |
| `ports_and_networking` | `EADDRINUSE :::3000`, `ECONNREFUSED`, sandbox DNS timeouts | `flowfuse`: Inject dynamic `$PORT`. `vega-lite`: `PUPPETEER_SKIP_DOWNLOAD=true`. `rxdb`: Pre-pin S3 DNS via `resolve-and-pin.sh`. |
| `memory_exhaustion` | JavaScript heap out of memory, SIGKILL, process exit 134 | `rxdb`: Export `NODE_OPTIONS="--max-old-space-size=8192"`. `uwazi`: Increase `container_cpus` in `config.json`. |
| `runner_env_config` | SQLite in-memory isolation, testTimeout ignored by runner | `flowfuse`: Inject `pool-shim.js` to isolate SQLite `:memory:` connections. `uwazi`: Inject `jest.setTimeout(60000)` into Jest setup. |

---

## Phased Triage Protocol

Follow this structured protocol when asked to analyze Jev's output.

> [!IMPORTANT]
> **Always talk to the user first after Phase 1.** Never dive head-first into investigating an unknown number of issues or individual logs without presenting the cluster overview and getting user confirmation on which issues to prioritize.

### Phase 1 — Summary, Discrepancy Matrix & Cluster Overview
Bounded scope: compile high-level statistics and cluster disagreements; do NOT inspect individual logs or commit diffs yet.

1. **Aggregate Stats:** Run `./check_failures_jev.py --project <p> --report` or summarize `projects/<p>/failure_labels_jev.csv`.
2. **Discrepancy Matrix:** Cross-reference `failure_labels_jev.csv` with human labels in `projects/<p>/failure_labels_project.csv`:
   - Agreement: (acceptable, acceptable), (reevaluated_acceptable, acceptable).
   - Discrepancy: (acceptable / reevaluated_acceptable, problematic), or any other mismatches.
3. **Cluster Grouping:** Group all problematic verdicts (`is_pipeline_issue == True`) and discrepancies into distinct failure families by underlying pattern/subsystem. For each family, map fingerprints to determine both:
   - The **unique failure signatures** (fingerprints),
   - The **total failure occurrences** (sum of `occurrences`),
   - The **actual distinct runs affected** across the project (not just the single exemplar `run_id`).
4. **Present Findings:**
   - Total signatures evaluated vs total failure occurrences.
   - Agreement vs disagreement matrix between Jev and Human labels.
   - Distinct clusters table: `Family / Signature | Subsystem | Exemplar Run | Unique Signatures | Total Occurrences | Actual Runs Affected | Human Label vs Jev Verdict`.

**Checkpoint 1 (Mandatory Stop Point):**
Present the summary table and discrepancy clusters. Ask the user:
> *"Here is the summary of discrepancies and failure clusters between Jev and the human labels (including affected runs and occurrences). Which cluster(s) would you like to investigate first, and in what order?"*
**STOP and wait for the user's response before proceeding to Phase 2.**

---

### Phase 2 — Targeted Causal Trace (Selected Clusters Only)
Bounded scope: investigate only the specific clusters or runs selected by the user.

For each selected cluster:
1. **Extract Log Context:** Open `projects/<p>/logs/<run_id>.log` around the reported line number to inspect the exact stack trace and error message.
2. **Inspect the Commit:** Run `git -C projects/<p>/repo show <hash> --stat` to see what changed in that commit.
3. **Check Immediate Follow-Up Commits:** Run `git -C projects/<p>/repo log --oneline <hash>..HEAD | head -n 5`.
   - Did the author push a fix commit immediately after (e.g., *"Fix tests after updating X"*)?
   - If yes: Document as **`reevaluated_acceptable`** (Author bug).
   - If no: Verify whether our container environment is missing a dependency or configuration.

**Checkpoint 2:**
Present the causal attribution findings for the investigated cluster(s). Ask:
> *"Should we adjust any labels for this cluster, dive into another cluster, or proceed to work orders?"*
Wait for user input before moving forward.

---

### Phase 3 — Actionable Work Order Formulation & Label Adjustments
For confirmed pipeline defects or agreed-upon label updates:
1. **Label Adjustments:** If human or Jev labels require updates (e.g. reclassifying a label or adding an entry), propose the exact changes to `failure_labels_project.csv` or `OVERVIEW.md`.
2. **Work Orders:** For confirmed pipeline defects, formulate a minimal, commit-era-aware recommendation for `install-and-run.sh` or `Dockerfile`.
   - Follow `AGENTS.md §6`: never apply unconditional global changes that risk breaking working historical eras; branch conditionally on package manager, detected files at checkout, or Node engine versions.
3. Output the prioritized fix order based on the number of commits/runs recovered.

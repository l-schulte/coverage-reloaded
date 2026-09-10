---
name: labeled-failure-analysis
description: Re-assess labeled problematic/unclear test failures using the project's failure_labels_project.csv and collapse_labels.py. Groups mislabeled/uncertain errors into families and, one-by-one, decides whether each is really an environment/setup problem and how to fix it in a commit-era-aware way. Static analysis only — no container runs without explicit permission.
license: MIT
metadata:
  audience: developers
  workflow: failure-analysis
---

## What I do

I consume the failures you already labeled with `check_failures.py` and re-assess them at the *family* level. Your `problematic` and `unclear` labels are treated as first-pass guesses; I decide for each error family whether it is:

- **really problematic** — an artifact of *our* pipeline/setup (the developer of that era would NOT have seen it),
- **actually acceptable** — a genuine dev-facing test failure you mislabeled (the developer of that era would have seen it too), or
- **genuinely unclear** — still ambiguous after best static effort.

For families that are really problematic, I recommend a fix. Every fix must be **commit-era-aware**: it applies conditionally across the commit range, tolerates evolutionary drift (different behavior in different eras), and must NOT break the other ~thousands of commits. I do not edit files — I only recommend.

## Context

- `check_failures.py --project <p> --dedup project` writes `projects/<p>/failure_labels_project.csv` (one row per failure fingerprint across all runs). Columns include `run_id` (`<ts>_<hash>`), `suite`, `exit_code`, `label` (`acceptable|problematic|unclear|false_positive`), `keyword`, `fingerprint`, `occurrences`.
- `collapse_labels.py <p>` reads that CSV and writes `projects/<p>/failure_labels_collapsed_problematic_unclear.csv`, collapsing only `problematic`+`unclear` rows into normalized error *families*. Each family row: `family_signature, label_breakdown, n_fingerprints, total_occurrences, n_runs, first_run, last_run, example_run_ids, example_keyword`.
- Per commit, a container runs `projects/<p>/install-and-run.sh`; logs at `projects/<p>/logs/<run_id>.log`. Ignore `logs_1/`, `output_1/`.
- `AGENTS.md §6`: fixes live in `install-and-run.sh` and must *read the commit, not dates* — branch on `$IS_NPM_MAIN_PM`/`$IS_YARN_MAIN_PM`/`$IS_PNPM_MAIN_PM`, on files present at the checked-out commit, and on node/pm versions. A single global change is forbidden.
- `AGENTS.md §3`: coverage-threshold gates (`--check-coverage`, `coverageThreshold`) are confounds, not bugs — do not recommend "fixing" them.
- `ENV_PATTERNS` (from `check_failures.py`): `Cannot find module`, `Cannot use import statement outside a module`, `Test suite failed to run`, `SyntaxError`, `EADDRINUSE`, `gyp ERR`, `Killed|out of memory|OOM`, webpack module/loader errors, `timed out|ETIMEDOUT|ECONNREFUSED|ENOTFOUND|EAI_AGAIN`, `node-sass|node-gyp|Missing binding`. A hit strongly implies *problematic* (our setup), not a real test failure.

## Iterative Protocol

Run phases sequentially. Stop after each phase. Present findings in full and wait for the user's explicit input at every checkpoint.

### Phase 0 — Prepare & Collapse

Bounded scope: get the data ready, no assessment yet.

1. Confirm `projects/<p>/failure_labels_project.csv` exists. If not, tell the user to run `python3 check_failures.py --project <p> --dedup project` first (labeling is their manual step) and stop.
2. Run `python3 collapse_labels.py <p>` (local CSV transform — no container, safe) to (re)generate `failure_labels_collapsed_problematic_unclear.csv`.
3. Report: number of families, source `problematic`/`unclear` row counts, and total `total_occurrences`.

**Checkpoint 0:** Show the collapsed summary table (sorted by `total_occurrences` desc): `family_signature | label_breakdown | n_fingerprints | total_occurrences | n_runs | first_run→last_run`. Ask: *"Which families should I assess, and in what priority order? (default: all, top-down by occurrences)"*

### Phase 1 — Family-by-family assessment (loop)

Process one selected family at a time. For each:

1. **Display the family card:** `family_signature`, `label_breakdown`, `n_fingerprints`, `total_occurrences`, `n_runs`, `first_run`→`last_run`, `example_run_ids`, and the full `example_keyword`.
2. **Trace root cause (static only):**
   - `run_id` = `<ts>_<hash>`. Read `projects/<p>/logs/<run_id>.log`; `grep` it for `example_keyword` and show the failure line plus ~40 lines below (mirror `print_context` in `check_failures.py`).
   - Extract `<hash>` and `git -C projects/<p>/repo show <hash>:` the era's `install-and-run.sh`, `package.json`, `Dockerfile`, and `projects/<p>/failure_patterns.json` to understand what the run actually did.
   - Apply the `ENV_PATTERNS` signals to the log context. A hit ⇒ lean *problematic*.
3. **Time-evolution check:** compare `first_run` vs `last_run` configs via `git show` at both ends. Is the cause era-specific (e.g., a node/pm-version boundary, a dependency that only existed in one window) or persistent across eras? This determines whether the fix must be conditional on era/version.
4. **Verdict (exactly one):**
   - `really problematic` — our setup; the developer of that era would not have hit it.
   - `actually acceptable` — you mislabeled a genuine dev-facing test failure.
   - `genuinely unclear` — ambiguous even after tracing.
5. **If problematic, recommend a fix** honoring these hard constraints:
   - **Era/commit-aware & non-breaking:** branch in `install-and-run.sh` on timestamp / pm / node version / files present at the commit (per AGENTS §6). Never a single global change.
   - **Tolerates drift:** if the cause only spans some commits, the branch must activate only for that range and stay inert elsewhere; note where the behavior should flip.
   - **Locate it:** (a) `install-and-run.sh` conditional edit (preferred), (b) `Dockerfile` system dep, or (c) document as known failure in `projects/<p>/OVERVIEW.md` "Known Test Failures" if unfixable.
   - **Exposure impact:** note whether it silently under-measures coverage (bail risk) or is an acceptable visible partial result.

**Checkpoint (per family):** Show the verdict + fix recommendation. Ask: *"Accept, modify, or skip this family?"* Always offer these three. Do not move on until answered.

### Phase 2 — Roll-up report

1. Compile every family into a table: `family_signature → verdict → root layer → conditional fix summary → fix location → commit time-span (#commits/#runs affected)`.
2. Group recommendations by action type: (a) `install-and-run.sh` conditional edits, (b) `Dockerfile` changes, (c) document-as-known in `OVERVIEW.md`.
3. Flag any coverage-threshold confounds encountered (AGENTS §3) as *not-bugs*.
4. Note remaining `unclear` families separately so the user can continue later.

**Checkpoint 2:** Show the completed report. Ask: *"Done — or continue with another family?"*

## Off-Limits — Strictly Enforced

The following require explicit, separate user permission. State what you intend to do, why, expected learnings, and duration — do not execute without confirmation.

- **No container launches / repro runs.** Do not `podman run|exec`, `bash docker-run.sh <p> shell|debug …`, or rerun `execute.sh` to verify a fix. All analysis is static: reading logs, `grep`, `git show`, config inspection, and running the local `collapse_labels.py` CSV transform.
- **Recommend only — no edits.** Do not modify `install-and-run.sh`, `Dockerfile`, `failure_patterns.json`, or any shared script during this skill. Produce recommendations for the user to apply.
- **Reasoning boundaries:** lead with a 3-sentence summary + one concrete next step; never a long speculative tree. After 2 attempts at a single family, escalate rather than keep digging. Hypotheses must pair with a concrete verification step (a `grep` pattern, a `git show` target, a file path).

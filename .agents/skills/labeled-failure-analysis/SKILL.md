---
name: labeled-failure-analysis
description: Re-assess labeled problematic/unclear test failures for one project using the v2 toolchain (check_failures_v2.py) — the deduped fp_min/fp_max label CSVs, the JSONL family cards, and the SQLite union run counts. Groups families and, one-by-one, decides whether each is really a pipeline/setup artifact, a dev-facing failure, or genuinely unclear, then recommends commit-era-aware fixes. Static analysis only — no container runs without explicit permission.
license: MIT
metadata:
  audience: developers
  workflow: failure-analysis
---

## What I do

I consume the failures you already labeled with `check_failures_v2.py` and re-assess them at the *family* level. Your `problematic` and `unclear` labels are treated as first-pass guesses; I decide for each error family whether it is:

- **really problematic** — an artifact of *our* pipeline/setup (the developer of that era would NOT have seen it),
- **actually acceptable** — a genuine dev-facing test failure you mislabeled (the developer of that era would have seen it too), or
- **genuinely unclear** — still ambiguous after best static effort.

For families that are really problematic, I recommend a fix. Every fix must be **commit-era-aware**: it applies conditionally across the commit range, tolerates evolutionary drift (different behavior in different eras), and must NOT break the other ~thousands of commits. I do not edit files — I only recommend.

## Context

### Toolchain & files

One project at a time (`<p>` = a directory under `projects/`), invoked from the repo
root. Every v2 artifact lives under `projects/<p>/label_analysis/`:

| Path | Role |
|---|---|
| `failure_patterns.json` | live config: detection patterns + `auto_classify` rules |
| `failure_labels_project_min.csv` | human labels, deduped by `fp_min` (primary window) |
| `failure_labels_project_max.csv` | human labels, deduped by `fp_max` (diagnostic window) |
| `failure_labels_jev_min.csv` | independent Jev labels (never written by a human) |
| `failure_labels_v2.db` | SQLite sidecar: `failures`, `labels`, `runs`, `meta` |
| `<p>_min.jsonl` | one family card per fingerprint, written by `--analyze` |
| `v1/` | retired v1 labels — reference only (see below) |

Commands:

```bash
python3 check_failures_v2.py <p> --build --window both    # scans output/, writes CSVs + DB (preserves existing labels)
python3 check_failures_v2.py <p> --progress --window both # labeled/manual/auto + fingerprint, detection, run coverage
python3 check_failures_v2.py <p> --stats                  # fingerprint statistics + union-run sanity
python3 check_failures_v2.py <p> --window min --analyze   # writes label_analysis/<p>_min.jsonl
python3 check_failures_v2.py <p> --window min --auto-classify
python3 check_failures_v2.py <p> --window min --verify     # drops stale fingerprints, then falls into labeling
python3 check_failures_v2.py <p> --window min --review <label>
python3 check_failures_v2.py <p> --window min --report-env # fingerprints whose context hits ENV_PATTERNS
python3 check_failures_v2.py <p> --crosscheck-v1          # optional consistency check against retired v1 labels
```

Per commit, a container runs `projects/<p>/install-and-run.sh`; logs are at
`projects/<p>/logs/<run_id>.log`, where `run_id = <ts>_<hash>`. Ignore `logs_1/`,
`output_1/`.

### Fingerprint model

- `fp_min` = trigger line + 2 following lines (3 lines); `fp_max` = trigger line + 5 following lines (6 lines). **min is the primary family**, max is the diagnostic/variant window. The two windows are labeled independently.
- Three distinct levels:
  1. **fingerprints** — deduped failure families (the labeling unit)
  2. **detections** — unique `(run, suite, fp_min, fp_max)` tuples
  3. **runs** — distinct commits with at least one failure
- **Blast radius is `COUNT(DISTINCT run_id)` over the family's fingerprints.** Never sum `n_runs` across families — co-occurring failures are counted once by a union and several times by a sum. (v1 summed to 12,188 against 626 failing runs in desktop: 19.5×.)

### ⚠️ Deduplication & the `run_id` Column (Exemplar vs. Real Blast Radius)

- **Each row is a unique fingerprint, not a single run.** The CSVs are deduped by `fp_min` / `fp_max`.
- **`run_id` is merely the exemplar** — the earliest chronological run where that fingerprint appeared. It does NOT mean the failure was confined to that run.
- **`n_runs` is the real blast radius** — the number of distinct runs the fingerprint occurred in, read from the SQLite sidecar.
- **Never report exemplar counts as run counts.** Any summary must distinguish:
  1. **unique fingerprints** (`n_fingerprints`),
  2. **detections** (rows in `failures`),
  3. **distinct runs affected** (union).

### v1 labels — reference only

A project may still carry artifacts from the retired v1 toolchain (`archive/check_failures.py`, `archive/collapse_labels.py`): `failure_labels_project.csv`, `failure_labels_jev.csv`, and `failure_labels_collapsed_*.csv`, at the project root or under `label_analysis/v1/`.

- They are **reference material, never a label source.** v2 labels are produced fresh with `check_failures_v2.py`; there is no label migration.
- If one influences anything I say, I disclose it in the session before it does — file path, row, and label, e.g. *"the v1 pass labeled this row `problematic`; treating that only as a hint."* Nothing from a v1 file is quoted as if it were a v2 finding.
- `--crosscheck-v1` maps v1 rows onto v2 detections by `(run_id, suite, line_number)` and writes `label_analysis/v1/<p>_v2_doublecheck.md`. It is an optional consistency check and gates nothing.
- The one-time migration in Phase 0 is performed by the user, not by me. After that, never move files into or out of `label_analysis/v1/`, never commit it (gitignored); the only write into it comes from `--crosscheck-v1` itself.

## Reclassification discipline

`unclear` and `problematic` are **starting** labels. Assessment must resolve them
to a final label — never leave a family as `unclear` after it has been assessed.

- **Transition model.** After assessing a family, apply exactly one transition:
  - `unclear` + genuinely problematic (setup artifact) → `problematic`
  - `unclear` + genuinely dev-facing → `reevaluated_acceptable`
  - `problematic` + genuinely dev-facing → `reevaluated_acceptable`
  - `problematic` + confirmed setup artifact → stays `problematic`
  `acceptable` and `false_positive` are final labels and do not transition.
- **Apply it everywhere.** The resolved label is written both to the matching rows
  in `failure_labels_project_min.csv` AND to the `auto_classify` rule that matches
  the error body in `failure_patterns.json`. A rule must not stay `unclear`/`problematic`
  once the family it detects has been resolved.
- **Regression persistence.** A rule's label is what future occurrences of that
  error body are auto-labeled with. Resolving a rule to `problematic` keeps a known
  setup artifact surfacing for review; `reevaluated_acceptable` records that the
  body was already assessed as dev-facing. Only update a rule when the whole family
  it detects has been assessed — reclassifying a single instance is not enough.
- **`reevaluated_acceptable` is a valid rule label** (member of `ALL_LABELS`), so
  `--auto-classify` applies it to new occurrences of the body. Setup artifacts stay
  labeled `problematic` so they resurface if the failure occurs.
- Relabeling by hand clears `auto_rule_id`; `--build` preserves whatever is in the
  CSVs, and `--auto-classify` re-applies the rules to unlabeled rows only.

## Labeling mechanics

Keys: ↑ acceptable, ↓ problematic, space unclear, → false_positive,
`e` reevaluated_acceptable, ← undo, `s` skip, `.` create auto rule, `r` reload
rules, `q` quit. The live counter shows
`[labeled/total · manual N · auto N · remaining N]`. `auto_rule_id` empty = manual
label; non-empty = auto-classified; `--progress` separates them.

Rules created with the `.` key carry `"generated_by": "check_failures_v2"` and
`"window": "min" | "max"` in `failure_patterns.json`, so they are distinguishable
from v1-generated rules (which have neither field).

Do not delete a label CSV to "reset" without asking — it removes your manual
labels. `--build` preserves labels by design.

## Iterative Protocol

Run phases sequentially. Stop after each phase. Present findings in full and wait for the user's explicit input at every checkpoint.

> [!IMPORTANT]
> **Always talk to the user first at Checkpoint 0.** Never dive head-first into deep-tracing logs or analyzing an unknown number of issues without presenting the overview and getting user confirmation on which families to prioritize.

### Phase 0 — Prepare & Inventory

Bounded scope: get the data ready, no assessment yet.

1. **Layout check.** Confirm `projects/<p>/label_analysis/failure_patterns.json` and
   `failure_labels_project_min.csv` exist.
   - If the project still has v1 files at the root (`failure_labels_project.csv`,
     `failure_labels_jev.csv`, collapsed CSVs), **stop and ask the user to migrate
     first**: move those into `projects/<p>/label_analysis/v1/` (gitignored), and
     move `failure_patterns.json` into `projects/<p>/label_analysis/` — it is live
     v2 config, not a v1 artifact. Do not move them yourself.
   - If `failure_patterns.json` is missing entirely, point the user at the
     `generate-failure-patterns` skill and stop.
2. **Build + recover auto labels** (state what it writes first; these commands
   write labels/rules, so proceed on the user's go-ahead):
   `python3 check_failures_v2.py <p> --build --window both`, then
   `python3 check_failures_v2.py <p> --window min --auto-classify` (recovers every
   auto label from `failure_patterns.json` for free; manual labels are redone by
   hand, which is expected).
3. **Family cards.** `python3 check_failures_v2.py <p> --window min --analyze` —
   each card carries `window, fingerprint, label, n_runs, n_variants, suites,
   first_run, last_run, example_run, line, keyword, block, auto_rule_id`. Read the
   JSONL instead of the multi-GB logs.
4. **Progress & statistics.** `--progress --window both` (labeled %, manual/auto
   split, fingerprint/detection/run coverage) and `--stats` (union-run sanity,
   fp_min variants). Optionally `--report-env`, and `--crosscheck-v1` if retired
   v1 labels exist.
5. **Rule-level rollup** (replaces v1's `collapse_labels.py`; read-only, from the
   JSONL cards + the DB + `failure_patterns.json`):

   ```python
   # python3 - — rule rollup for window=min
   import json, sqlite3, collections
   p = "<project>"; an = f"projects/{p}/label_analysis"
   cards = [json.loads(l) for l in open(f"{an}/{p}_min.jsonl")]
   rules = {r.get("id", ""): r for r in
            json.load(open(f"{an}/failure_patterns.json")).get("auto_classify", [])}
   con = sqlite3.connect(f"{an}/failure_labels_v2.db")
   def union(fps):                       # exact run union, never a sum
       runs = set()
       for i in range(0, len(fps), 900):
           c = fps[i:i + 900]
           runs.update(r[0] for r in con.execute(
               f"SELECT DISTINCT run_id FROM failures WHERE fp_min IN "
               f"({','.join('?' * len(c))})", c))
       return len(runs)
   groups = collections.defaultdict(list)
   for c in cards:
       groups[c["auto_rule_id"] or "(manual)"].append(c)
   for rid, g in sorted(groups.items(), key=lambda kv: -union([c["fingerprint"] for c in kv[1]])):
       rule = rules.get(rid, {})
       print(f"{rid:<24} {rule.get('match', '-'):40.40} {rule.get('label', '-'):<26}"
             f" {len(g):>4} fp  {union([c['fingerprint'] for c in g]):>5} runs  "
             f"{min(c['first_run'] for c in g)}..{max(c['last_run'] for c in g)}  "
             f"{dict(collections.Counter(c['label'] for c in g))}")
   ```

   Caveats to state when using it: `auto_rule_id` is **label provenance**, not
   current rule membership — a manually relabeled family leaves its rule group
   while the rule still exists; unlabeled fingerprints have no rule and land in
   `(manual)` / omitted; `rule_pattern` and `rule_label` come from
   `failure_patterns.json` because the DB stores only the id. The v1 "signature
   view" is the same grouping keyed on `keyword` instead of `auto_rule_id`.

**Checkpoint 0 (Mandatory Stop Point):** Show the rule rollup sorted by union runs in the snippet's column order:
`rule_id | rule_pattern | rule_label | n_fingerprints | union n_runs | first_run..last_run | label_breakdown`, plus the top ~20 fingerprint families by `n_runs` (label, `n_variants`, example `keyword`), plus the `--progress` block (labeled %, manual vs auto, run coverage). Then ask: *"Which families should I assess, and in what priority order? (default: all, top-down by union runs)"*
**STOP and wait for the user's response before proceeding to Phase 1.**

### Phase 1 — Family-by-family assessment (loop)

Process one selected family at a time (prioritizing the rule view):

1. **Display the family card:** `auto_rule_id` / fingerprint, `rule_pattern`, `label_breakdown`, `n_fingerprints`, union `n_runs`, `first_run`→`last_run`, `suites`, `example_run`, `line`, `keyword`, and the recorded `block`.
2. **Trace root cause (static only):**
   - If assessing a broad rule family (e.g. `● Test suite failed to run`), first decompose its cards into sub-families: same `rule_pattern` but distinct `keyword` / `block` / suites.
   - `run_id` = `<ts>_<hash>`. Read `projects/<p>/logs/<run_id>.log`; `grep` it for `example_keyword` (or `line`) and show the failure line plus ~40 lines below (mirror `print_context`: `--context-above 4 --context-below 40`).
   - Extract `<hash>` and `git -C projects/<p>/repo show <hash>:` the era's `install-and-run.sh`, `package.json`, `Dockerfile`, and `projects/<p>/label_analysis/failure_patterns.json` to understand what the run actually did.
   - Apply the `ENV_PATTERNS` signals: `Cannot find module`, `Cannot use import statement outside a module`, `Test suite failed to run`, `SyntaxError`, `EADDRINUSE`, `gyp ERR`, `Killed|out of memory|OOM`, webpack module/loader errors, `timed out|ETIMEDOUT|ECONNREFUSED|ENOTFOUND|EAI_AGAIN`, `node-sass|node-gyp|Missing binding`. A hit ⇒ lean *problematic*; `--report-env` lists every fingerprint whose context hits them. Verify against the commit tree — a local `Cannot find module` is often genuine.
3. **Time-evolution check:** compare `first_run` vs `last_run` configs via `git show` at both ends. Is the cause era-specific (e.g., a node/pm-version boundary, a dependency that only existed in one window) or persistent across eras? This determines whether the fix must be conditional on era/version.
4. **Flags to inspect:** `n_variants > 1` (the 6-line window captured volatile context — SHA, frame, value; the min block may already be the right family); min/max disagreements (same `(run_id, suite, line)` labeled differently in the two windows).
5. **Verdict (exactly one):**
   - `really problematic` — our setup; the developer of that era would not have hit it.
   - `actually acceptable` — you mislabeled a genuine dev-facing test failure.
   - `genuinely unclear` — ambiguous even after tracing.

   For `actually acceptable`, record the family's rows and the matching
   `auto_classify` rule as `reevaluated_acceptable`. For `really problematic`,
   record both as `problematic`. Never leave the family as `unclear` (see
   Reclassification discipline).
6. **If problematic, recommend a fix** honoring these hard constraints:
   - **Era/commit-aware & non-breaking:** branch in `install-and-run.sh` on timestamp / pm / node version / files present at the commit (per AGENTS §6). Never a single global change.
   - **Tolerates drift:** if the cause only spans some commits, the branch must activate only for that range and stay inert elsewhere; note where the behavior should flip.
   - **Locate it:** (a) `install-and-run.sh` conditional edit (preferred), (b) `Dockerfile` system dep, or (c) document as known failure in `projects/<p>/OVERVIEW.md` "Known Test Failures" if unfixable.
   - **Exposure impact:** note whether it silently under-measures coverage (bail risk) or is an acceptable visible partial result.
7. **Close the loop after a fix is applied and re-run.** Once the user has applied a fix and re-run the affected commits:
   - Tell the user to run `python3 check_failures_v2.py <p> --window min --verify`. This drops labels whose fingerprint no longer occurs in the current output, then falls straight into the normal labeling flow, so only newly-changed failures are re-presented. The family's `auto_classify` rule stays `problematic`, so a regression is re-detected and resurfaces rather than being hidden — never relabel a real pipeline defect to `reevaluated_acceptable` just to clear it from the view.
   - After re-labeling, run `--build --window both` and `--progress --window both`, then continue with the remaining families.

**Checkpoint (per family):** Show the verdict + fix recommendation. Ask: *"Accept, modify, or skip this family?"* Always offer these three. Do not move on until answered.

### Phase 2 — Roll-up report

1. Compile every family into a table: `family (rule_id / fingerprint) → verdict → root layer → conditional fix summary → fix location → commit time-span (#commits / union #runs affected)`.
2. Group recommendations by action type: (a) `install-and-run.sh` conditional edits, (b) `Dockerfile` changes, (c) document-as-known in `OVERVIEW.md`.
3. Flag any coverage-threshold confounds encountered (AGENTS §3: `--check-coverage`, `coverageThreshold`, custom wrappers) as *not-bugs*.
4. Report min/max label disagreements and (if `--crosscheck-v1` was run) the v1 disagreements still unresolved.
5. Note remaining `unclear` families separately so the user can continue later.

**Checkpoint 2:** Show the completed report. Ask: *"Done — or continue with another family?"*

## Guardrails

- Generic skill, one project at a time; no project-specific code. Project differences belong in `failure_patterns.json` (patterns, suites, `min_gap`; future normalization hooks).
- **Normalization policy is Tier 0 only:** ANSI, timing suffixes, the exact repo prefix, blank-run collapsing, source coordinates (`foo.ts:123:45` → `foo.ts:<n>:<n>`). No generic volatile-token detection. Do **not** add Tier 1 (UUID/hex/ports/temp paths) or Tier 2 (numbers/stack frames) without explicit approval. Consequences to accept: `/tmp/desktop-test-*` stays split by path; `fp_max` may split on SHAs or stack frames — the min window is the stable one.
- Do not edit the archived v1 scripts (`archive/check_failures.py`, `archive/collapse_labels.py`, `archive/check_failures_jev.py`); they are frozen by decision. Do not edit any `install-and-run.sh` from this skill.
- Never commit `label_analysis/v1/`; never move files in or out of it (only the user's one-time migration in Phase 0 and `--crosscheck-v1`'s artifact touch that directory).
- Preserve user labels: never overwrite a CSV without reading it first, never delete a CSV as a reset.
- **Validate on desktop before another project:** the known collision (`branch-test.ts` across dark-theme/SyntaxError/Electron) must split into distinct fp_min families, the `assertNever` TS6133 family must stay stable in `fp_min`, and jest re-prints must collapse (the `failures` primary key `(run_id, suite, fp_min, fp_max)`).
- Never present a sum of `n_runs` as a run count. Use unions.
- Read-only analysis commands (`--progress`, `--stats`, `--analyze`, `--report-env`, `--crosscheck-v1`, `--dry-run`) may be run directly. Label- or rule-writing commands (`--build`, `--auto-classify`, `--verify`, `--review`, interactive labeling) only on the user's explicit instruction.

## Off-Limits — Strictly Enforced

The following require explicit, separate user permission. State what you intend to do, why, expected learnings, and duration — do not execute without confirmation.

- **No container launches / repro runs.** Do not `podman run|exec`, `bash docker-run.sh <p> shell|debug …`, or rerun `execute.sh` to verify a fix. All analysis is static: reading logs, `grep`, `git show`, config inspection, and the read-only commands listed above.
- **Recommend only — no edits.** Do not modify `install-and-run.sh`, `Dockerfile`, `failure_patterns.json`, or any shared script during this skill. Produce recommendations for the user to apply.
- **Reasoning boundaries:** lead with a 3-sentence summary + one concrete next step; never a long speculative tree. After 2 attempts at a single family, escalate rather than keep digging. Hypotheses must pair with a concrete verification step (a `grep` pattern, a `git show` target, a file path).

---
name: check-failures-v2
description: Build, label, and analyze per-project failure fingerprints with check_failures_v2.py. Covers the two windows (fp_min = 3 lines, fp_max = 6 lines), the two deduped label CSVs, the SQLite run-set sidecar, progress/statistics, JSONL family cards, and the correct union-run metric. Generic for all projects, one at a time; desktop is the validation project.
license: MIT
metadata:
  audience: developers
  workflow: failure-analysis
---

## What I do

I operate `check_failures_v2.py` for one project at a time. v2 replaces the v1
fingerprint (a `test:`/`file:` identity extracted from a scan window) with a
**hash of the error block itself**, in two sizes:

- `fp_min` — trigger line + 2 following lines (3 lines total)
- `fp_max` — trigger line + 5 following lines (6 lines total)

v1 could give the same fingerprint to a file that failed for different reasons
(dark-theme, SyntaxError, Electron, …). v2 makes those distinct. v1 is not
modified; v2 writes new files.

## Why the metric matters (the v1 bug)

`occurrences` is the number of distinct runs for **one fingerprint**. Summing it
across fingerprints double-counts runs that produce several failures. In desktop
v1 the CSV summed to 12,188 against 626 failing runs (19.5×). Never use a sum of
`occurrences` as a blast radius.

Three distinct levels:

1. **fingerprints** — deduped failure families (the labeling unit)
2. **detections** — unique `(run, suite, fp_min, fp_max)` tuples
3. **runs** — distinct commits with at least one failure

For a family, the blast radius is `COUNT(DISTINCT run_id)` over the relevant
fingerprint(s), which the SQLite sidecar answers. `--progress`, `--stats`, and
`--analyze` already report the correct union.

## Files

Everything lives under `projects/<p>/label_analysis/`:

```
projects/<p>/
  label_analysis/
    failure_patterns.json              # live config (read + written by v2)
    failure_labels_project_min.csv     # human labels, deduped by fp_min
    failure_labels_project_max.csv     # human labels, deduped by fp_max
    failure_labels_jev_min.csv         # Jev labels (independent)
    failure_labels_v2.db               # failures / labels / runs / meta
    <p>_min.jsonl                      # family cards (--analyze)
    v1/                                # RETIRED v1 artifacts — gitignored
      failure_labels_project.csv       # v1 human labels (reference only)
      failure_labels_jev.csv           # v1 Jev labels (reference only)
      <p>_v2_doublecheck.md            # double-check pass artifact

check_failures_v2.py            # thin wrapper
check_failures_jev_v2.py        # independent Jev labeler (thin wrapper)
failure_triage/                 # implementation package
  config.py normalize.py fingerprint.py detect.py store.py
  label.py metrics.py jev.py jev_provider.py cli.py paths.py
```

Labels live in the CSVs; `--build` re-reads them and preserves them. The SQLite
`labels` table mirrors the CSVs. `failures` stores every detection; its primary
key `(run_id, suite, fp_min, fp_max)` collapses jest re-prints.

**Path resolution** (`failure_triage/paths.py`): `failure_patterns.json` and
the v1 CSVs are looked up in `label_analysis/` first, then at the project
root — both layouts work, so not-yet-migrated projects are unaffected. All v2
outputs are always written into `label_analysis/`. Nothing is ever written
into `label_analysis/v1/` except the double-check artifact.

## Commands

```bash
# scan output/ once, write both CSVs + SQLite
python3 check_failures_v2.py <project> --build --window both

# labeling progress (fingerprints / detections / runs, manual vs auto)
python3 check_failures_v2.py <project> --progress --window both

# fingerprint statistics + progress
python3 check_failures_v2.py <project> --stats

# interactive labeling on the primary (min) window; live counter
python3 check_failures_v2.py <project> --window min

# bulk-apply failure_patterns.json -> auto_classify rules
python3 check_failures_v2.py <project> --window min --auto-classify

# drop labels whose fingerprint no longer occurs, then label
python3 check_failures_v2.py <project> --window min --verify

# re-display an existing label class
python3 check_failures_v2.py <project> --window min --review unclear

# JSONL family cards
python3 check_failures_v2.py <project> --window min --analyze

# cross-check retired v1 labels against v2; writes the double-check
# artifact to label_analysis/v1/<project>_v2_doublecheck.md (gitignored)
python3 check_failures_v2.py <project> --crosscheck-v1

# Jev v2 (independent labels): count + sample, then a y/N confirmation
python3 check_failures_jev_v2.py --project <project> --dry-run --limit 5
python3 check_failures_jev_v2.py --project <project> --report
python3 check_failures_jev_v2.py --project <project>        # asks before API
```

Jev v2 reuses the v2 fingerprints and SQLite sidecar, writes
`failure_labels_jev_min.csv`, never touches the human CSVs, and shows the number
of items before spending API tokens. `--yes` skips the confirmation (use only
when the count is already known); `--dry-run` never calls the API.

Labeling keys: ↑ acceptable, ↓ problematic, space unclear, → false_positive,
`e` reevaluated_acceptable, ← undo, `s` skip, `.` create auto rule, `r` reload
rules, `q` quit. The live counter shows
`[labeled/total · manual N · auto N · remaining N]`.

## Normalization policy

**Tier 0 only, for now:** ANSI, timing suffixes, the exact repo prefix,
blank-run collapsing, source coordinates (`foo.ts:123:45` → `foo.ts:<n>:<n>`).
No generic volatile-token detection. Do **not** add Tier 1 (UUID/hex/ports/
temp paths) or Tier 2 (numbers/stack frames) without explicit approval.

Consequences to accept:
- `/tmp/desktop-test-*` stays split by path (hundreds of fingerprints).
- 6-line `fp_max` may split on commit SHAs, stack frames, or code-frame lines.
  That is what the min/max comparison exposes; the min window is the stable one.

## Labeling policy

- Label **min** as the primary family; **max** is the diagnostic/variant window.
- Labels are independent per window.
- `auto_rule_id` empty = manual label; non-empty = auto-classified. The progress
  block separates them.
- Rules created from v2 with the `.` key carry
  `"generated_by": "check_failures_v2"` and `"window": "min" | "max"` in
  `failure_patterns.json`, so they can be told apart from v1-generated rules
  (which have neither field).
- Do not delete a label CSV to “reset” without asking; it also removes the
  user's manual labels. `--build` preserves labels by design.

## v1 → v2 retirement & double-check

The v1 toolchain (`check_failures.py`, `check_failures_jev.py`) is archived
at `archive/v1_check_failures/` and frozen — it does not follow the new paths
and is expected to be broken for migrated projects.

**Before starting v2 on a project**, the user moves the v1 artifacts into
`label_analysis/v1/` (gitignored by decision): `failure_labels_project.csv`,
`failure_labels_jev.csv`, and any collapsed CSVs (already gitignored).
`failure_patterns.json` is moved to `label_analysis/` (it is live v2 config,
not a v1 artifact).

There is **no label migration.** v2 labeling is done fresh:
`--auto-classify` recovers every auto label from `failure_patterns.json` for
free; manual v1 labels are re-done by hand (this extra effort is expected).
The v1 CSVs remain only as a cross-check reference.

**Double-check gate — run before a project's v2 labels count as complete:**

1. `--progress --window both` — labeled %, manual/auto split, run coverage.
2. `--stats` — fingerprint/union-run sanity (watch for fingerprint blow-up
   relative to the v1 counts printed in the progress block).
3. `--crosscheck-v1` — matches v1 labeled rows onto v2 detections by
   `(run_id, suite, line_number)`; both toolchains share the detection pass,
   so every v1 row should still be found. It checks:
   - **unmatched v1 rows** — each must be explained (pattern drift vs a v2
     detection miss); the count must not just be waved through;
   - **label conflicts** — one v2 family mapped from v1 rows with different
     labels (the v1 collision bug resurfacing); must be zero;
   - **label agreement** on matched detections; disagreements get reviewed;
   - **min/max disagreements** — one detection labeled differently in the
     two windows.
   It writes `label_analysis/v1/<project>_v2_doublecheck.md` (gitignored)
   with the results plus a checklist; record the final PASS verdict in that
   artifact after the manual steps.
4. Desktop regression guardrails (see Guardrails): known collision splits,
   `assertNever` family stable, jest re-prints collapse.
5. `--review` each label class once; read the top families in the JSONL.

Only after the artifact records PASS is the project's v2 considered
complete. The retired v1 files stay in `label_analysis/v1/` permanently —
never re-imported as labels, never committed.

## Analysis workflow

1. `--analyze` writes one JSONL card per fingerprint:
   `window, fingerprint, label, n_runs, n_variants, suites, first_run, last_run,
   example_run, line, keyword, block, auto_rule_id`.
2. Read the JSONL instead of the multi-GB logs. Rank by `n_runs` (union), not by
   summed occurrences.
3. Flags to inspect:
   - `n_variants > 1` — the 6-line window contains volatile context (SHA, frame,
     value). The min block may already be the right family.
   - `env_signals` / `ENV_PATTERNS` — lean problematic, but verify against the
     commit tree (a local `Cannot find module` is often genuine).
   - min/max disagreements — same `(run_id, suite, line)` labeled differently.
4. Feed the family cards into `labeled-failure-analysis` for verdicts and fixes;
   that skill's CSV/collapse instructions are v1 — use the v2 JSONL cards as the
   family source.

## Guardrails

- Generic script, one project at a time; no project-specific code in the script.
  Project differences belong in `failure_patterns.json` (patterns, suites,
  `min_gap`; future normalization hooks).
- Do not edit the archived v1 scripts (`archive/v1_check_failures/`) or make
  them follow the new paths; they are frozen by decision. Do not edit any
  `install-and-run.sh` from this skill.
- Never commit `label_analysis/v1/` (gitignored by decision) and never move
  files out of it, except writing the double-check artifact into it.
- No container runs; this is log/CSV/SQLite analysis only.
- Preserve user labels; never overwrite a CSV without reading it first.
- Validate on desktop before another project: the known collision
  (`branch-test.ts` across dark-theme/SyntaxError/Electron) must split, the
  `assertNever` TS6133 family must stay stable in `fp_min`, and jest re-prints
  must collapse.
- Do not present a sum of `occurrences` as a run count. Use unions.

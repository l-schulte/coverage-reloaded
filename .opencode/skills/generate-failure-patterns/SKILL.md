---
name: generate-failure-patterns
description: Derive and propose a per-project failure_patterns.json for check_failures.py. Analyzes the project's install-and-run.sh and the unsuffixed logs/ folder to learn the actual test-runner output, then proposes tight failure-detection patterns that anchor on the REAL error (not just the failing test name). Draft-and-confirm only — it writes the file only after the user approves. Does NOT touch auto_classify (that is manual work done with check_failures.py).
license: MIT
metadata:
  audience: developers
  workflow: failure-triage-setup
---

## What I do

For a single project, I produce a candidate `projects/<name>/failure_patterns.json`
that `check_failures.py` consumes to find failures inside non-zero-exit test runs.
The file has two relevant blocks (the third, `auto_classify`, is **off-limits** here):

- `general.patterns` / `general.exclude` — the base failure markers and noise filters.
- `suites["<suite>"].add_patterns` / `remove_patterns` / `add_exclude` / `remove_exclude`
  — additive per-suite overrides (the runner is often different per suite).

**Critical requirement:** patterns must mark the *start of the real error*, not the
*failing test's name or file* line. A loose `FAIL\s` or `\bfailed\b` often lands on a
test-name/file header that is followed by many more test names before the actual error
appears — that pollutes the `keyword` column and can double-count. I derive anchors
**empirically from the project's own logs**, never from a blind hardcoded table, and I
verify each anchor by reading the lines *below* it in the log.

**`auto_classify` is NEVER written by this skill.** It stays an empty array `[]` (or is
left untouched if the file already exists). Those rules map an error *body* to a label
(acceptable / problematic / unclear / false_positive) and are built manually by you,
interactively, with `check_failures.py` (press `.` on a failure to create a rule). Do not
attempt to guess labels or seed auto_classify here.

When the user later creates `auto_classify` rules, start unresolved patterns as
`problematic`/`unclear` so a genuine setup regression is surfaced for review, and
resolve them to `problematic` or `reevaluated_acceptable` once the detected family
has been assessed (see the `labeled-failure-analysis` skill). `reevaluated_acceptable`
and `fix_applied` are valid rule labels.

## Context (how check_failures.py uses this file)

- `projects/<name>/output/<ts>_<hash>/<suite>.exit_code` (0 = clean, 1 = tests failed but
  coverage valid, >1 = runner crashed) drives which run logs are scanned.
- For each such run, the matching log is `projects/<name>/logs/<ts>_<hash>.log`.
- Inside that log, `check_failures.py` finds `[SUITE_START] <suite>` … `[SUITE_END] <suite>`
  spans and, within each span, flags a line as a failure if it matches any `patterns` regex
  AND does not match any `exclude` regex.
- On a hit, it shows `context-below=40` lines, so the real error is *usually* visible even
  if the matched line is slightly upstream — but the matched line's TEXT becomes the
  `keyword` stored in `failure_labels.csv`, so it must itself be meaningful.
- `min-gap` (default 5) and a normalized-block fingerprint dedupe jest's re-prints, so a
  single failure reported twice collapses. Still, prefer ONE tight anchor per failure kind
  to keep the `keyword` column clean.

## Invocation

Run for **one project at a time**, named explicitly:

> generate failure patterns for `<name>`

where `<name>` is a directory under `projects/`. Read everything from
`projects/<name>/` (relative to the `coverage_reloaded` repo root). Use the **unsuffixed**
`projects/<name>/logs/` directory only — ignore `logs_1/`, `logs_2/`, etc.

## Phased protocol (draft & confirm — stop before writing)

### Phase 1 — Inventory suites and runners

1. Read `projects/<name>/install-and-run.sh`. Enumerate every `suite_start "<s>"` marker
   (these are the suite names `check_failures.py` will key on). Record, per suite, the test
   command it wraps (jest / mocha / vitest / karma / ava / tap / web-component-tester / …)
   by inspecting the command between `suite_start` and `suite_end`.
2. Confirm each suite actually appears in the logs: grep `projects/<name>/logs/*.log` for
   `[SUITE_START] <s>`. Drop from scope any suite that never ran (no span in any log).
3. **Checkpoint-1 output** (do not write yet): a table

   ```
   Suite        | Runner  | Seen in logs? | Notes
   -------------|---------|---------------|-------
   unit         | jest    | yes           | --runInBand
   integration  | mocha   | yes           | wrapped with nyc
   ```

### Phase 2 — Sample real failure blocks per suite

For each suite, pick a few `.log` files where that suite's `[SUITE_END]` is preceded by a
non-zero exit (or just grep the suite span for failure markers) and extract the raw block
around a failure. Do this by reading the log files directly (the model, not
`check_failures.py`). Look for the *native* failure vocabulary of that runner, for example:

- **jest / vitest:** `✕ <test>`, `● <suite> › <test>` (the detailed error header that sits
  **directly above** the actual error), `FAIL <path> (Ns)` (file header), `Tests: N failed`,
  `Expected ... Received ...`, `AssertionError`, stack `at <file>:<line>:<col>`.
- **mocha:** `failing`, `AssertionError`, `Error:`, stack traces, `N passing`, `M failing`.
- **karma / webpack:** `ERROR`, `webpack: Failed to compile`, `Chrome ... Error`.
- **ava / tap:** `✖`, `not ok`, `expected ... got ...`.

### Phase 3 — Propose tight anchors (the core task)

**You (the model) propose the patterns.** For each suite/runner, choose the marker that sits
*immediately upstream of the real error text* and justify it. Prefer the detailed-error
header over the file-name header. Here are concrete include/exclude examples to reason from:

**Include (patterns) — pick the line co-located with the error:**

- jest: prefer `●` (the `● suite › test` line is printed right before the thrown error /
  `Expected`/`Received` block) and `✕` over `FAIL\s`.
  - ❌ `"FAIL\\s"` — matches `FAIL integration-tests/structured-logging/__tests__/to-do.js (6s)`,
    a file-name line; the real error is far below and the `keyword` would be just the path.
  - ✅ `"●"` — matches `● develop › initial work finishes … › emit initial SET_STATUS …`, which
    is printed immediately above the actual assertion failure.
  - ✅ `"✕"` — the per-test failure tick, also near the error.
- mocha: `"AssertionError"`, `"\\bError:"`, `"\\bfailing\\b"` — these sit on/above the stack.
- Generic last-resort (only if no runner marker is consistently near the error):
  `"\\bAssertionError"`, `"\\bTypeError"`, `"\\bReferenceError"`, `"\\bRangeError"`.

**Exclude (noise that is NOT a failure start):**

- `"Test Suites:"`, `"Tests:"`, `"Snapshots:"` — jest summary lines (the run already exited
  non-zero; these are aggregates, not a failure location).
- `"●\\s*Console"` — jest's captured-console dump (a `● Console` block is not a failure).
- `"Ran all test suites"` — jest footer.
- `"console\\."` — per-line console output captured inside a suite.
- `"at "` / `"\\s+at \\S"` — raw stack-trace lines (these are *part of* an error body, not its
  start; including them double-counts). Only include `at ...` if it is the first line of an
  error in that runner and nothing tighter exists.
- Any project-specific persistent footer (e.g. a custom reporter line) observed in Phase 2.

Build the structure:

```json
{
  "general": {
    "patterns": [ "<runner-agnostic anchors that work for MOST suites>" ],
    "exclude":  [ "<noise seen across suites>" ]
  },
  "suites": {
    "<suite>": {
      "remove_patterns": [ "..." ],
      "add_patterns":    [ "..." ],
      "remove_exclude":  [ "..." ],
      "add_exclude":     [ "..." ]
    }
  },
  "auto_classify": []
}
```

Rules for composition:
- Put the **common** anchors in `general.patterns` (e.g. `✕`, `●`, `AssertionError`) and
  common noise in `general.exclude`.
- Use a suite block only to **fix drift**: if suite `integration` is mocha while `general` is
  jest-shaped, `add_patterns: ["AssertionError","\\bError:"]` and `remove_patterns: ["✕","●"]`.
- **Always show the reasoning** for each chosen/omitted pattern (the include/exclude examples
  above are the template). Do not emit a pattern you cannot justify against a sampled log line.
- Leave `auto_classify` as `[]`. Never populate it.

### Phase 4 — Self-validate before showing

1. Write the candidate JSON to a **temp** path (e.g. `/tmp/failure_patterns.<name>.json`).
2. Run `python check_failures.py --project <name> --dry-run` to confirm detections fire at all
   and to see how many `(suite, line)` hits per run. A zero hit-count on runs that clearly
   failed means the patterns are too tight — loosen.
3. **Verify the anchors reveal the true error:** for a sample of detected `(run_id, line)`
   pairs, open `projects/<name>/logs/<run_id>.log` and read lines `[line-2 .. line+40]`.
   Confirm the block shows the actual error (assertion / stack / `Expected`/`Received`), not
   just a test-name list. If a sampled hit lands on a test-name line, tighten that pattern
   (e.g. drop `FAIL\s`, switch to `●`) and re-run. Iterate until the sample is clean.
4. Also sanity-check per-suite counts (print them for the user) so they can eyeball coverage
   before approving — e.g. "unit: 312 detections across 88 runs; integration: 47 across 30".

### Phase 5 — Present & confirm (no write until approved)

Print the full proposed `failure_patterns.json` and a short rationale per suite, plus the
validation counts from Phase 4. Then stop and ask:

> "Proposed failure_patterns.json for `<name>` (detection-only; auto_classify left empty).
> Approve to write it to `projects/<name>/failure_patterns.json`?"

Only after explicit approval, write the file (pretty-printed, trailing newline). If the file
already exists, back it up to `failure_patterns.json.bak` first and preserve any pre-existing
`auto_classify` entries verbatim (do not overwrite the user's manual rules).

## Guardrails (strictly enforced)

- **No `auto_classify` content** — ever. Empty array only. Labeling is the user's manual job
  via `check_failures.py` (`.` key creates a rule).
- No `FAIL\s` / `failed` / bare `Error` unless Phase-2 logs prove the anchor is adjacent to
  the real error.
- Never modify shared pipeline scripts (`check_failures.py`, `execute.sh`,
  `find-and-move-lcov.sh`, `logging.sh`) or `install-and-run.sh`.
- Use the **unsuffixed** `logs/` directory only; ignore `logs_N/`.
- Do not run containers; this is read-only log analysis + a dry-run validation on the host.
- When unsure whether a pattern reveals the true error, prefer the tighter anchor and show the
  evidence line from the log.

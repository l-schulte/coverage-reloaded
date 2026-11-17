# JeV audit — compass

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)
**Snapshot:** mode `fingerprint`; rows `172` (172 current fingerprints, 0 stale rows); flagged `is_pipeline_issue == True` `56` (`runner_env_config`: `27`, `false_positive`: `17`, `none`: `8`, `ports_and_networking`: `4`); JeV `labeled_at` max `2026-11-17T13:01:10Z`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-11-17T09:02:06Z`; fingerprints `172`)

Audit performed against the corpus produced by the 2026-11-16/17 path-reconciliation and residual flake re-runs (`6,260` commits, `0` pending, `6,210` logs / `50` `.error`).

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| **A** jsdom `Error: Could not parse CSS stylesheet` (`compass-aggregations`, `compass-crud`, `compass-schema`, `compass-schema-validation`, `compass-saved-aggregations-queries`) | 2023-10-26 … 2024-08-19 · `1698332392_62adbfce` | 5 | `runner_env_config` | jsdom's virtual console logs a CSS parse error while `@emotion/sheet`/`stylis` inject a `<style>` node (`jsdom/…/stylesheets.js:37`). The suite is green: `694 passing`, `0 failing`, `All files 90.01 %`. The fingerprint exists only because `failure_patterns.json` treats `\b[A-Za-z0-9_]*Error:` as a trigger. Three identical-mechanism fingerprints (`compass-home`, `compass-query-bar`, `compass-web`) were labelled `False` by the same model at the same 0.51–0.56 confidence. | upstream defect — **not a failure** (labelling artifact; human `acceptable`) |
| **B** `Attempt N failed Error: port 27021/27022 is open` and `Server port is already closed … port is closed` | 2023-05-23 … 2023-07-12 · `1684844943_e9cdb6c0` | 4 | `ports_and_networking` | Upstream's own `scripts/testserver.js` teardown SIGKILLs `mongod` and polls until the port closes (`assertPortClosed`, l.192, inside `retry`, l.117). Attempt 1 loses the race, attempt 2 logs `27021 is closed`. Emitted in `posttest`, i.e. **after** the coverage table (`243 passing`, `All files 80.58 %`). Deterministic: 204 of 205 runs of the suite. | upstream defect — **false positive** (human `false_positive`) |
| **C** `All files \| 0 \| 0 \| 0 \| 0 \|` (`@mongodb-js/compass-instance`) | 2022-01-18 … 2022-11-19 | 13 | `false_positive` | `1a6ac32a1b` (2021-12-21) deleted `src/plugin.spec.js` while `test` stayed `mocha-webpack "./src/**/*.spec.js"`; the glob matches nothing (`0 passing (0ms)`, `Tests completed successfully`). Confirmed at `dd8cde2ff0` (2022-03-09): the only spec left is the `test/renderer/store.spec.js` placeholder. Ends at the upstream migration `bb1a39e78c` (`test: mocha`). See the detection caveat in `OVERVIEW.md` → Known gaps: only 43 of 1,688 zero-table runs are inside a run the scanner reads. | upstream defect — **documented gap** (human `acceptable`) |
| **D** `> node -e "…skipping standalone electron smoke suite…"` | 2021-11-15 … 2022-02-23 | 13 | `runner_env_config` (5) / `none` (5) / `false_positive` (3) | The text of the harness' own Electron-skip stub, promoted to a trigger by the `skipping (?:standalone )?electron smoke suite` pattern. Affected packages exit 0; the rest of each run is green. | **false positive** (human `acceptable`/`false_positive`) |
| **E** `TypeError: textRange(...).getClientRects is not a function` (`compass-shell`, `compass-aggregations`) | 2023-02-16 … 2023-03-20 · `1676538788_3fc468b0` | 2 | `runner_env_config` | CodeMirror measures DOM geometry (`EditorView.coordsAtPos` → `textRange(...).getClientRects`) that jsdom does not implement; thrown inside jsdom's animation-frame callback and merely logged. Same run: `compass-shell 47 passing`, `compass-aggregations 472 passing`, 0 failing. | upstream defect — **not a failure** (human `acceptable`) |
| **G** `ENOENT … open '/tmp/s-…'` (`importCSV → correctly imports long (windows)`) | 2023-05-15 … 2023-05-18 | 15 | `runner_env_config` | `097c9604c5` duplicated the `temp.createWriteStream()` / `readFile(output.path)` assertion inside a new `unix`/`windows` loop, so the read-back races the write stream. Mongo chased it as the *importCSV CI flake* (#4394) and removed the assertion in `2fe2a32345` (#4397), the last failing commit. | **upstream test race** (human `reevaluated_acceptable`) |

Union of the 56 flagged fingerprints: **986 runs**. Families A–E are the same failure
seen through a trigger pattern (console message / retry chatter / zero-coverage table / stub
echo) rather than a test failure; none of them touches the container, the Dockerfile or the
registry mirror.

## Conclusion

**Zero confirmed pipeline defects in the current corpus.** The historical `mongos` defect
(`d35fd33a3b1c8a18`) was permanently fixed and verified (167/167 runs passing clean), and
that stale candidate has now dropped from the active fingerprint set.

The 56 flagged fingerprints are commit-era or labelling artefacts (jsdom logs, upstream
teardown chatter, the documented `compass-instance` gap, and upstream test hook races). No
active JeV flag traces to the container, the harness, or the registry mirror.

## Label outcome

- Remaining `acceptable`: **128** (+ 37 `reevaluated_acceptable`, 7 `false_positive`).
- Reclassified `reevaluated_acceptable` in this audit round: none new — the 15 `importCSV`
  fingerprints and the 22 `1a5273f74cdb` runs were already reclassified from the earlier
  labelled-failure pass.
- Remaining `problematic`: **0**.
- Remaining `unclear`: **0**.

## Method notes

- **100% active fingerprint coverage.** All 172 rows in `failure_labels_jev_min.csv` match
  the 172 active human fingerprints in `failure_labels_project_min.csv` 1:1 with zero stale rows.
- **Cross-check scope.** JeV was audited in fingerprint mode across all 172 candidates. The `max`
  window and the dedup-keyword/error artefacts were not re-generated.

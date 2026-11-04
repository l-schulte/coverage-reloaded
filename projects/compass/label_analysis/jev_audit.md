# JeV audit — compass

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)
**Snapshot:** mode `fingerprint`; rows `178` (176 current fingerprints + 2 stale rows, see
Method notes); flagged `is_pipeline_issue == True` `53` (`runner_env_config`: `27`,
`false_positive`: `16`, `none`: `6`, `ports_and_networking`: `4`), of which `52` are current
fingerprints; JeV `labeled_at` max `2026-11-04T18:51:30Z`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max
`2026-11-04T12:16:56Z`; fingerprints `176`)

Audit performed against the corpus produced by the 2026-11-03/04 re-runs plus the 2026-11-04
sharded-cluster batch (`6,260` commits, `0` pending, `6,210` logs / `50` `.error`).

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| **A** jsdom `Error: Could not parse CSS stylesheet` (`compass-aggregations`, `compass-crud`, `compass-schema`, `compass-schema-validation`, `compass-saved-aggregations-queries`) | 2023-10-26 … 2024-08-19 · `1698332392_62adbfce` | 5 | `runner_env_config` | jsdom's virtual console logs a CSS parse error while `@emotion/sheet`/`stylis` inject a `<style>` node (`jsdom/…/stylesheets.js:37`). The suite is green: `694 passing`, `0 failing`, `All files 90.01 %`. The fingerprint exists only because `failure_patterns.json` treats `\b[A-Za-z0-9_]*Error:` as a trigger. Three identical-mechanism fingerprints (`compass-home`, `compass-query-bar`, `compass-web`) were labelled `False` by the same model at the same 0.51–0.56 confidence. | upstream defect — **not a failure** (labelling artifact; human `acceptable`) |
| **B** `Attempt N failed Error: port 27021/27022 is open` and `Server port is already closed … port is closed` | 2023-05-23 … 2023-07-12 · `1684844943_e9cdb6c0` | 4 | `ports_and_networking` | Upstream's own `scripts/testserver.js` teardown SIGKILLs `mongod` and polls until the port closes (`assertPortClosed`, l.192, inside `retry`, l.117). Attempt 1 loses the race, attempt 2 logs `27021 is closed`. Emitted in `posttest`, i.e. **after** the coverage table (`243 passing`, `All files 80.58 %`). Deterministic: 204 of 205 runs of the suite. | upstream defect — **false positive** (human `false_positive`) |
| **C** `All files \| 0 \| 0 \| 0 \| 0 \|` (`@mongodb-js/compass-instance`) | 2022-01-18 … 2022-11-19 | 13 | `false_positive` | `1a6ac32a1b` (2021-12-21) deleted `src/plugin.spec.js` while `test` stayed `mocha-webpack "./src/**/*.spec.js"`; the glob matches nothing (`0 passing (0ms)`, `Tests completed successfully`). Confirmed at `dd8cde2ff0` (2022-03-09): the only spec left is the `test/renderer/store.spec.js` placeholder. Ends at the upstream migration `bb1a39e78c` (`test: mocha`). See the detection caveat in `OVERVIEW.md` → Known gaps: only 43 of 1,688 zero-table runs are inside a run the scanner reads. | upstream defect — **documented gap** (human `acceptable`) |
| **D** `> node -e "…skipping standalone electron smoke suite…"` | 2021-11-15 … 2022-02-23 | 13 | `runner_env_config` (5) / `none` (5) / `false_positive` (3) | The text of the harness' own Electron-skip stub, promoted to a trigger by the `skipping (?:standalone )?electron smoke suite` pattern. Affected packages exit 0; the rest of each run is green. | **false positive** (human `acceptable`/`false_positive`) |
| **E** `TypeError: textRange(...).getClientRects is not a function` (`compass-shell`, `compass-aggregations`) | 2023-02-16 … 2023-03-20 · `1676538788_3fc468b0` | 2 | `runner_env_config` | CodeMirror measures DOM geometry (`EditorView.coordsAtPos` → `textRange(...).getClientRects`) that jsdom does not implement; thrown inside jsdom's animation-frame callback and merely logged. Same run: `compass-shell 47 passing`, `compass-aggregations 472 passing`, 0 failing. | upstream defect — **not a failure** (human `acceptable`) |
| **G** `ENOENT … open '/tmp/s-…'` (`importCSV → correctly imports long (windows)`) | 2023-05-15 … 2023-05-18 | 15 | `runner_env_config` | `097c9604c5` duplicated the `temp.createWriteStream()` / `readFile(output.path)` assertion inside a new `unix`/`windows` loop, so the read-back races the write stream. Mongo chased it as the *importCSV CI flake* (#4394) and removed the assertion in `2fe2a32345` (#4397), the last failing commit. | **upstream test race** (human `reevaluated_acceptable`) |

Union of the 52 current flagged fingerprints: **985 runs**. Families A–E are the same failure
seen through a trigger pattern (console message / retry chatter / zero-coverage table / stub
echo) rather than a test failure; none of them touches the container, the Dockerfile or the
registry mirror.

## Conclusion

**One confirmed pipeline defect in the whole flagged set**, and it was identified and fixed
during this audit:

- **`d35fd33a3b1c8a18` — missing `mongos`.** `09d1c368` (2025-11-10) added the repository's only
  sharded-cluster test (`packages/data-service/src/data-service.spec.ts` → `with real sharded
  cluster`). `mongodb-runner@5.11` starts that topology by spawning `<binDir>/mongos`; the image
  shipped only `mongod`, so the spawn raised `ENOENT`, which `MongoServer.start`'s catch handler
  turned into `TypeError: Cannot read properties of undefined (reading 'some')`
  (`err.errorLogEntries.some(...)`). Fixed in `projects/compass/Dockerfile` (extract `bin/mongos`
  for 4.4–8.0, link `/usr/local/bin/mongos`) and `install-and-run.sh` (symlink `bin/mongos` into
  the mongodb-runner downloader cache). Verified on `09d1c368` (209 passing, 0 failing,
  `#fetchShardKey` and `#indexes … includes the shard key` executing) and across the full batch:
  **167/167** commits now execute the sharded context. The fingerprint no longer occurs, which is
  why that JeV row is now stale.

The other 52 flagged fingerprints are commit-era or labelling artefacts (jsdom logs, upstream
teardown chatter, the documented `compass-instance` gap, and the upstream `importCSV` race). No
JeV flag other than the `mongos` one traces to the container, the harness, or the registry mirror.

## Label outcome

- Remaining `acceptable`: **132** (+ 37 `reevaluated_acceptable`, 7 `false_positive`).
- Reclassified `reevaluated_acceptable` in this audit round: none new — the 15 `importCSV`
  fingerprints and the 22 `1a5273f74cdb` runs were already reclassified from the earlier
  labelled-failure pass.
- Remaining `problematic`: **0**. The single work order (`mongos`) is applied and verified;
  its detection rule is not retained, because the fingerprint cannot recur once the binary
  exists in the image.

## Method notes

- **Two stale rows.** `d35fd33a3b1c8a18` (the `mongos` TypeError, fixed above) and
  `c6218c35b91fbc89` (a `compass-import-export` assertion that did not recur) remain in the JeV
  CSV with their verdicts but no longer match any current human fingerprint. The file is
  generated by the labeller and is never edited by hand, so they were left in place; effective
  coverage is **176/176** current fingerprints.
- **Last unlabelled item required a payload fix.** `bb7289da7b9f1502` (a single
  `AssertionError` whose serialized DOM dump is **24,064 characters** on one line) was rejected by
  Eden AI with `max_tokens_exceeded`. `failure_triage/jev_provider.py` now clips each snippet line
  to 400 characters and the whole snippet to 8,000 in `build_state_for_item` (payload ~27k → 3,894
  chars). JeV then answered **acceptable, 0.77, `runner_env_config`**, agreeing with the human
  label. This affects only what is sent to the provider, not fingerprints or stored labels.
- **Cross-check scope.** JeV was audited in fingerprint mode only. The `max` window and the
  dedup-keyword/error artefacts were not re-generated.

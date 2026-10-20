"""Labeling progress, fingerprint statistics and analysis."""

import collections
import csv
import datetime
import json
import os

from . import paths, store


def _window_name(window):
    return "min" if window == 2 else "max"


def window_counts(con, window):
    col = "fp_min" if window == 2 else "fp_max"
    return dict(con.execute(
        f"SELECT {col}, COUNT(DISTINCT run_id) FROM failures GROUP BY {col}"
    ).fetchall())


def do_progress(project, con, window):
    """Labeling progress for one window: fingerprints, detections, runs."""
    name = _window_name(window)
    col = "fp_min" if window == 2 else "fp_max"
    rows = store.load_csv(paths.csv_path(project, window))
    total = len(rows)
    labeled_rows = [r for r in rows if r.get("label")]
    unlabeled = total - len(labeled_rows)
    labels = collections.Counter(r["label"] for r in labeled_rows)
    auto = sum(1 for r in labeled_rows if r.get("auto_rule_id"))
    manual = len(labeled_rows) - auto
    rules = collections.Counter(r["auto_rule_id"] for r in labeled_rows
                                if r.get("auto_rule_id"))

    print(f"\nwindow={name} ({'3 lines' if window == 2 else '6 lines'})")
    print(f"  fingerprints: {total}")
    if total:
        print(f"  labeled:      {len(labeled_rows)} ({len(labeled_rows)/total*100:.1f}%) "
              f"[manual {manual}, auto {auto}]")
        print(f"  unlabeled:    {unlabeled} ({unlabeled/total*100:.1f}%)")
    print(f"  labels:       {dict(labels)}")
    if rules:
        print(f"  top rules:    {rules.most_common(5)}")

    if con is None:
        return
    total_det = con.execute("SELECT COUNT(*) FROM failures").fetchone()[0]
    total_runs = con.execute("SELECT COUNT(DISTINCT run_id) FROM failures").fetchone()[0]
    if not total_det or not total_runs:
        return
    fps = [r["fingerprint"] for r in labeled_rows]
    covered_det = 0
    runs = set()
    for chunk in store.chunks(fps):
        ph = ",".join("?" * len(chunk))
        covered_det += con.execute(
            f"SELECT COUNT(*) FROM failures WHERE {col} IN ({ph})", chunk
        ).fetchone()[0]
        runs.update(x[0] for x in con.execute(
            f"SELECT DISTINCT run_id FROM failures WHERE {col} IN ({ph})", chunk
        ).fetchall())
    print(f"  coverage:     detections {covered_det}/{total_det} "
          f"({covered_det/total_det*100:.1f}%), "
          f"runs {len(runs)}/{total_runs} ({len(runs)/total_runs*100:.1f}%)")

    v1_path = paths.v1_labels_path(project)
    if os.path.isfile(v1_path):
        v1 = store.load_csv(v1_path)
        v1l = collections.Counter(r.get("label") or "unlabeled" for r in v1)
        print(f"  v1 reference: {len(v1)} fingerprints, {dict(v1l)}")


def do_stats(project, con):
    if con is None:
        print("[error] --stats needs the SQLite sidecar")
        return
    n_runs = con.execute("SELECT COUNT(DISTINCT run_id) FROM failures").fetchone()[0]
    print(f"failing runs: {n_runs}")
    for window in (2, 5):
        name = _window_name(window)
        col = "fp_min" if window == 2 else "fp_max"
        fps = window_counts(con, window)
        if not fps:
            continue
        multi = sum(1 for v in fps.values() if v > 1)
        union = con.execute("SELECT COUNT(DISTINCT run_id) FROM failures").fetchone()[0]
        print(f"\nwindow={name} ({'3 lines' if window == 2 else '6 lines'})")
        print(f"  fingerprints: {len(fps)}")
        print(f"  fingerprints in >1 run: {multi}")
        print(f"  sum of per-fp runs: {sum(fps.values())}  "
              f"(double-counts co-occurring failures)")
        print(f"  failing runs (union): {union}")
        if window == 2:
            var = con.execute(
                "SELECT fp_min, COUNT(DISTINCT fp_max) v FROM failures "
                "GROUP BY fp_min HAVING v > 1"
            ).fetchall()
            print(f"  fp_min with >1 fp_max variant: {len(var)}")
            labels = dict(con.execute(
                "SELECT fp, label FROM labels WHERE window='min'").fetchall())
        else:
            labels = dict(con.execute(
                "SELECT fp, label FROM labels WHERE window='max'").fetchall())
        top = sorted(fps.items(), key=lambda kv: -kv[1])[:10]
        print("  top fingerprints by union runs:")
        for fp, n in top:
            variants = con.execute(
                f"SELECT COUNT(DISTINCT {'fp_max' if window == 2 else 'fp_min'}) "
                f"FROM failures WHERE {col}=?", (fp,)
            ).fetchone()[0]
            print(f"    {n:5} runs  variants={variants:2}  "
                  f"label={labels.get(fp, '-'):22} {fp}")


def do_analyze(project, window, con):
    if con is None:
        print("[error] --analyze needs the SQLite sidecar")
        return
    out_dir = paths.analysis_dir(project)
    os.makedirs(out_dir, exist_ok=True)
    name = _window_name(window)
    col = "fp_min" if window == 2 else "fp_max"
    rows = store.load_csv(paths.csv_path(project, window))
    if not rows:
        print(f"[error] no rows in {paths.csv_path(project, window)}")
        return
    jsonl_path = os.path.join(out_dir, f"{project}_{name}.jsonl")
    cards = []
    for r in rows:
        fp = r["fingerprint"]
        n_runs = con.execute(
            f"SELECT COUNT(DISTINCT run_id) FROM failures WHERE {col}=?", (fp,)
        ).fetchone()[0]
        suites = [x[0] for x in con.execute(
            f"SELECT DISTINCT suite FROM failures WHERE {col}=?", (fp,)
        ).fetchall()]
        variants = con.execute(
            f"SELECT COUNT(DISTINCT {'fp_max' if window == 2 else 'fp_min'}) "
            f"FROM failures WHERE {col}=?", (fp,)
        ).fetchone()[0]
        lab = r.get("label") or "unlabeled"
        cards.append({
            "window": name, "fingerprint": fp, "label": lab,
            "n_runs": n_runs, "n_variants": variants, "suites": suites,
            "first_run": r["first_run"], "last_run": r["last_run"],
            "example_run": r["run_id"], "line": r["line_number"],
            "keyword": r["keyword"], "block": r["block"],
            "auto_rule_id": r.get("auto_rule_id", ""),
        })
    cards.sort(key=lambda c: -c["n_runs"])
    with open(jsonl_path, "w") as f:
        for c in cards:
            f.write(json.dumps(c) + "\n")
    print(f"wrote {jsonl_path}")


def do_crosscheck(project, con):
    """Cross-check the retired v1 labels against the v2 fingerprint set.

    v1 is a *reference*, never a label source. Matched on
    (run_id, suite, line_number) — both toolchains share the detection pass,
    so the trigger line of a v1 row must still exist as a v2 detection:

    - unmatched v1 labeled rows = pattern drift or a v2 detection miss;
      each one must be explained before the project passes the double-check.
    - label conflicts = one v2 family mapped from v1 rows with different
      labels (the v1 collision bug resurfacing; must be zero).
    - label agreement = matched detections whose v2 family already has a
      label; disagreements need review.
    - min/max disagreements = one detection whose fp_min and fp_max carry
      different labels.

    The report is written to label_analysis/v1/<project>_v2_doublecheck.md
    (gitignored); the final PASS verdict is appended manually.
    """
    if con is None:
        print("[error] --crosscheck-v1 needs the SQLite sidecar")
        return
    v1_path = paths.v1_labels_path(project)
    v1 = store.load_csv(v1_path)
    if not v1:
        print(f"[error] no v1 reference CSV at {v1_path}")
        return
    min_rows = store.load_csv(paths.csv_path(project, 2))
    if not min_rows:
        print(f"[error] no v2 CSV at {paths.csv_path(project, 2)}; "
              "run --build first")
        return

    v1_labeled = [r for r in v1 if r.get("label")]
    v1_dist = collections.Counter(r["label"] for r in v1_labeled)
    keys = {}
    dupes = []
    for r in v1_labeled:
        k = (r["run_id"], r["suite"], int(r["line_number"]))
        if k in keys:
            dupes.append(k)
        else:
            keys[k] = r

    det = con.execute(
        "SELECT run_id, suite, line_number, fp_min FROM failures").fetchall()
    matched = [d for d in det if (d[0], d[1], d[2]) in keys]
    fp_of = {}
    fp_labels = collections.defaultdict(set)
    for run, suite, line, fp in matched:
        fp_of[(run, suite, line)] = fp
        fp_labels[fp].add(keys[(run, suite, line)]["label"])
    conflicts = {fp: sorted(labs) for fp, labs in fp_labels.items()
                 if len(labs) > 1}
    unmatched = [k for k in keys if k not in fp_of]

    v2_label_of = {r["fingerprint"]: r["label"]
                   for r in min_rows if r.get("label")}
    agree = disagree = 0
    disagreements = []
    for k, fp in fp_of.items():
        v2l = v2_label_of.get(fp)
        if not v2l:
            continue
        v1l = keys[k]["label"]
        if v1l == v2l:
            agree += 1
        else:
            disagree += 1
            if len(disagreements) < 20:
                disagreements.append((k, v1l, v2l, fp))

    max_rows = store.load_csv(paths.csv_path(project, 5))
    max_label_of = {r["fingerprint"]: r["label"]
                    for r in max_rows if r.get("label")}
    mm = {}
    for fpmin, fpmax in con.execute(
            "SELECT DISTINCT fp_min, fp_max FROM failures").fetchall():
        a, b = v2_label_of.get(fpmin), max_label_of.get(fpmax)
        if a and b and a != b:
            mm[(fpmin, fpmax)] = (a, b)

    pct = len(fp_of) / len(keys) * 100 if keys else 0.0
    lines = [
        f"# v2 double-check — {project}",
        "",
        "Generated by `check_failures_v2.py "
        f"{project} --crosscheck-v1` on "
        f"{datetime.date.today().isoformat()}.",
        "",
        "## v1 reference (label_analysis/v1/, gitignored)",
        "",
        f"- v1 CSV: `{v1_path}`",
        f"- v1 labeled rows: {len(v1_labeled)} {dict(v1_dist)}",
        f"- v1 rows sharing (run, suite, line): {len(dupes)}",
        "",
        "## v1 -> v2 matching (window=min)",
        "",
        f"- v2 detections: {len(det)}",
        f"- matched v1 labeled rows: {len(fp_of)}/{len(keys)} "
        f"({pct:.1f}%)",
        f"- distinct v2 fp_min touched: {len(fp_labels)}",
        f"- label conflicts within one v2 family: {len(conflicts)}",
        f"- unmatched v1 labeled rows: {len(unmatched)}",
        "",
    ]
    for fp, labs in sorted(conflicts.items())[:20]:
        lines.append(f"- CONFLICT `{fp}`: {labs}")
    if conflicts:
        lines.append("")
    for k in unmatched[:20]:
        r = keys[k]
        lines.append(f"- unmatched {k[0]} {k[1]} L{k[2]} "
                     f"label={r['label']} {r.get('keyword', '')[:70]}")
    if len(unmatched) > 20:
        lines.append(f"- ... and {len(unmatched) - 20} more")
    lines += [
        "",
        "## label agreement (matched detections with a labeled v2 family)",
        "",
        f"- agree: {agree}, disagree: {disagree}",
        "",
    ]
    for k, v1l, v2l, fp in disagreements:
        lines.append(f"- {k[0]} {k[1]} L{k[2]}: v1={v1l} v2={v2l} (`{fp}`)")
    lines += [
        "",
        "## min/max label disagreements",
        "",
        f"- {len(mm)} detection pairs labeled differently across windows",
        "",
    ]
    for (fpmin, fpmax), (a, b) in list(sorted(mm.items()))[:20]:
        lines.append(f"- min `{fpmin}`={a} vs max `{fpmax}`={b}")
    lines += [
        "",
        "## Verdict",
        "",
        "- [ ] unmatched v1 rows explained (pattern drift vs v2 miss)",
        "- [ ] no unresolved label conflicts",
        "- [ ] label disagreements reviewed",
        "- [ ] manual checklist done (see the labeled-failure-analysis skill)",
        "- result: pending",
        "",
    ]
    os.makedirs(paths.v1_dir(project), exist_ok=True)
    path = paths.doublecheck_path(project)
    with open(path, "w") as f:
        f.write("\n".join(lines))
    print(f"matched {len(fp_of)}/{len(keys)} v1 labeled rows "
          f"({pct:.1f}%), conflicts={len(conflicts)}, "
          f"disagreements={disagree}, min/max disagreements={len(mm)}")
    print(f"wrote {path}")

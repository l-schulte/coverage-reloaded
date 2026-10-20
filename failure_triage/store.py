"""CSV label files and the SQLite run-set sidecar."""

import csv
import os
import sqlite3

from . import paths

CSV_FIELDS = [
    "project", "window", "run_id", "suite", "exit_code", "line_number",
    "keyword", "label", "labeled_at", "fingerprint", "n_runs", "n_variants",
    "example_variant_fp", "auto_rule_id", "first_run", "last_run", "block",
]


def load_csv(path):
    if not os.path.isfile(path):
        return []
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def save_csv(path, rows):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in CSV_FIELDS})


def load_label_map(path):
    out = {}
    for r in load_csv(path):
        if r.get("label"):
            out[r["fingerprint"]] = (r["label"], r.get("labeled_at", ""),
                                     r.get("auto_rule_id", ""))
    return out


def build_csv_rows(project, window, families):
    """Deduped rows for one window, labels preserved from the existing CSV."""
    path = paths.csv_path(project, window)
    labels = load_label_map(path)
    rows = []
    for fp, rec in families[window].items():
        ex = rec["exemplar"]
        lab, at, rid = labels.get(fp, ("", "", ""))
        rows.append({
            "project": project,
            "window": "min" if window == 2 else "max",
            "run_id": ex["run_id"],
            "suite": ex["suite"],
            "exit_code": ex["exit_code"],
            "line_number": ex["line"],
            "keyword": ex["text"],
            "label": lab,
            "labeled_at": at,
            "fingerprint": fp,
            "n_runs": len(rec["runs"]),
            "n_variants": len(rec["variants"]),
            "example_variant_fp": (sorted(rec["variants"])[0] if rec["variants"] else ""),
            "auto_rule_id": rid,
            "first_run": rec["first"],
            "last_run": rec["last"],
            "block": ex["block"],
        })
    rows.sort(key=lambda r: (r["first_run"], r["line_number"]))
    return rows


def open_db(path):
    con = sqlite3.connect(path)
    con.execute("""CREATE TABLE IF NOT EXISTS failures (
        run_id TEXT, suite TEXT, line_number INTEGER,
        fp_min TEXT, fp_max TEXT, trigger TEXT, exit_code INTEGER,
        PRIMARY KEY (run_id, suite, fp_min, fp_max))""")
    con.execute("CREATE INDEX IF NOT EXISTS idx_fail_min ON failures(fp_min)")
    con.execute("CREATE INDEX IF NOT EXISTS idx_fail_max ON failures(fp_max)")
    con.execute("CREATE INDEX IF NOT EXISTS idx_fail_run ON failures(run_id)")
    con.execute("""CREATE TABLE IF NOT EXISTS labels (
        window TEXT, fp TEXT, label TEXT, labeled_at TEXT, auto_rule_id TEXT,
        PRIMARY KEY (window, fp))""")
    con.execute("""CREATE TABLE IF NOT EXISTS runs (
        run_id TEXT PRIMARY KEY, timestamp INTEGER, exit_code INTEGER)""")
    con.execute("""CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY, value TEXT)""")
    con.execute("INSERT OR REPLACE INTO meta VALUES ('schema_version', '2')")
    con.commit()
    return con


def write_db(con, failures, runs, label_rows):
    con.execute("DELETE FROM failures")
    con.execute("DELETE FROM runs")
    con.executemany(
        "INSERT OR IGNORE INTO failures VALUES (?,?,?,?,?,?,?)",
        [(f["run_id"], f["suite"], f["line"], f["fp_min"], f["fp_max"],
          f["text"], f["exit_code"]) for f in failures],
    )
    con.executemany(
        "INSERT OR REPLACE INTO runs VALUES (?,?,?)",
        [(rid, int(rid.split("_")[0]) if rid.split("_")[0].isdigit() else 0, code)
         for rid, code in runs.items()],
    )
    con.executemany(
        "INSERT OR REPLACE INTO labels VALUES (?,?,?,?,?)", label_rows,
    )
    con.commit()


def chunks(values, n=900):
    for i in range(0, len(values), n):
        yield values[i:i + n]

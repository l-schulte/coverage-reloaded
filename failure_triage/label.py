"""Interactive labeling, auto-classify, verify and review."""

import os
import re
import sys
import termios
import tty
from datetime import datetime, timezone

from . import config, detect, metrics, paths, store
from .normalize import clean, env_signals, normalize_line

LABELS = {
    "UP": "acceptable",
    "DOWN": "problematic",
    " ": "unclear",
    "RIGHT": "false_positive",
    "e": "reevaluated_acceptable",
}


def match_auto_rule(lines, fail_line, rules, default_region=12):
    start = fail_line - 1
    for stored, label, _note, n, rid in rules:
        if not stored:
            continue
        region = max(default_region, (n or 5) + 4)
        text = "\n".join(normalize_line(l) for l in lines[start:start + region])
        try:
            if re.compile(stored).search(text):
                return label, rid
        except re.error:
            continue
    return None


def item_body(lines, fail_line, n=5):
    start = fail_line - 1
    if n == 0:
        body = lines[start:start + 1]
    else:
        body = lines[start + 1:start + 1 + n]
    return "\n".join(normalize_line(l) for l in body)


def get_key():
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = sys.stdin.read(1)
        if ch == "\x03":
            raise KeyboardInterrupt
        if ch == "\x1b":
            sys.stdin.read(1)
            ch3 = sys.stdin.read(1)
            return {"A": "UP", "B": "DOWN", "C": "RIGHT", "D": "LEFT"}.get(ch3, "ESC")
        return ch
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def print_context(lines, fail_line, c_above=4, c_below=40):
    lo = max(1, fail_line - c_above)
    hi = min(len(lines), fail_line + c_below)
    print("\n" + "─" * 72)
    for i in range(lo, hi + 1):
        marker = "▶" if i == fail_line else " "
        print(f"{marker} {i:5}: {clean(lines[i - 1])}")
    print("─" * 72)
    print("↑ acceptable   ↓ problematic   space unclear   → false_positive   "
          "e re-eval   . rule   r reload   ← undo   s skip   q quit")


def row_to_item(row, project, window):
    lines = detect.iter_log_lines(project, row["run_id"])
    if lines is None:
        return None
    return {"row": row, "lines": lines, "line": int(row["line_number"])}


def label_rows(project, window, args, con):
    path = paths.csv_path(project, window)
    rows = store.load_csv(path)
    if not rows:
        print(f"[error] no rows in {path}; run --build first")
        return
    rules = config.load_auto_rules(project)
    c_above, c_below = args.context_above, args.context_below
    total = len(rows)

    def save():
        store.save_csv(path, rows)
        if con is not None:
            con.executemany(
                "INSERT OR REPLACE INTO labels VALUES (?,?,?,?,?)",
                [(("min" if window == 2 else "max"), r["fingerprint"], r["label"],
                  r["labeled_at"], r["auto_rule_id"]) for r in rows if r["label"]],
            )
            con.commit()

    def done_count():
        return sum(1 for r in rows if r.get("label"))

    history = []
    labeled = auto_labeled = skipped = 0
    i = 0
    while i < len(rows):
        rules = config.load_auto_rules(project)
        row = rows[i]
        if args.only_unlabeled and row.get("label"):
            i += 1
            continue
        item = row_to_item(row, project, window)
        if item is None:
            print(f"[warn] missing log for {row['run_id']}")
            i += 1
            continue
        done = done_count()
        manual = sum(1 for r in rows if r.get("label") and not r.get("auto_rule_id"))
        res = match_auto_rule(item["lines"], item["line"], rules)
        if res is not None:
            lab, rid = res
            row["label"] = lab
            row["labeled_at"] = datetime.now(timezone.utc).isoformat()
            row["auto_rule_id"] = rid
            save()
            labeled += 1
            auto_labeled += 1
            print(f"  [{done + 1}/{total}] auto-labeled {lab}: {row['keyword'][:60]}")
            i += 1
            continue

        print(f"\n[{done}/{total} labeled · manual {manual} · auto {done - manual} · "
              f"{total - done} remaining] "
              f"{row['run_id']} {row['suite']} L{row['line_number']} "
              f"fp={row['fingerprint']} n_runs={row['n_runs']} variants={row['n_variants']}")
        print_context(item["lines"], item["line"], c_above, c_below)
        k = get_key()
        if k in LABELS:
            prev = dict(row)
            row["label"] = LABELS[k]
            row["labeled_at"] = datetime.now(timezone.utc).isoformat()
            row["auto_rule_id"] = ""
            history.append((i, prev))
            save()
            labeled += 1
            print(f"  -> labeled {LABELS[k]}  [{done + 1}/{total}]")
            i += 1
        elif k == ".":
            print("  body lines below trigger [5] (0 = matched line only): ",
                  end="", flush=True)
            try:
                ans = input().strip()
            except EOFError:
                ans = ""
            n = 0 if ans == "0" else (int(ans) if ans.isdigit() and 1 <= int(ans) <= 60 else 5)
            lab = row.get("label")
            if not lab:
                print("  choose label: ↑ acceptable ↓ problematic space unclear "
                      "→ false_positive e re-eval")
                kk = get_key()
                if kk not in LABELS:
                    print("  -> no label chosen, rule not created")
                    i += 1
                    continue
                lab = LABELS[kk]
                row["label"] = lab
                row["labeled_at"] = datetime.now(timezone.utc).isoformat()
                save()
            body = item_body(item["lines"], item["line"], n)
            rid = config.add_auto_rule(project, body, lab, lines=n,
                                       window=("min" if window == 2 else "max"))
            print(f"  -> rule created (label={lab}, lines={n}, id={rid})")
            i += 1
        elif k == "LEFT":
            if history:
                pos, prev = history.pop()
                rows[pos] = prev
                save()
                labeled -= 1
                i = pos
                print("  -> undo")
            else:
                print("  -> nothing to undo")
        elif k == "s":
            skipped += 1
            print(f"  -> skipped  [{done}/{total} labeled]")
            i += 1
        elif k in ("r", "R"):
            rules = config.load_auto_rules(project)
            res = match_auto_rule(item["lines"], item["line"], rules)
            if res is not None:
                lab, rid = res
                row["label"] = lab
                row["labeled_at"] = datetime.now(timezone.utc).isoformat()
                row["auto_rule_id"] = rid
                save()
                labeled += 1
                auto_labeled += 1
                print(f"  -> reloaded, auto-labeled {lab}")
                i += 1
            else:
                print("  -> reloaded, no match")
        elif k in ("q", "ESC"):
            break
    save()
    print(f"done. labeled={labeled} auto-labeled={auto_labeled} skipped={skipped}")
    metrics.do_progress(project, con, window)


def do_verify(project, window, cfg, args, con):
    path = paths.csv_path(project, window)
    rows = store.load_csv(path)
    if not rows:
        print(f"[error] no rows in {path}; run --build first")
        return
    out_root = args.output_dir or os.path.join(paths.project_dir(project), "output")
    min_gap = args.min_gap if args.min_gap is not None else int(cfg.get("min_gap", 5))
    families, _failures, _runs = detect.scan(
        project, cfg, out_root, min_gap, args.suite, [window],
    )
    live = set(families[window])
    kept, dropped = [], []
    for r in rows:
        (kept if r["fingerprint"] in live else dropped).append(r)
    if dropped:
        store.save_csv(path, kept)
        print(f"verify: dropped {len(dropped)} labels whose fingerprint no longer occurs")
        for r in dropped[:10]:
            print(f"  - {r['fingerprint']} {r['keyword'][:60]}")
    else:
        print("verify: nothing to drop")
    if kept and not args.verify_only:
        label_rows(project, window, args, con)


def do_review(project, window, args, con):
    path = paths.csv_path(project, window)
    rows = store.load_csv(path)
    filtered = [r for r in rows if r.get("label") == args.review]
    if not filtered:
        print(f"no labels with class {args.review!r}")
        return
    cur = 0
    while cur < len(filtered):
        row = filtered[cur]
        item = row_to_item(row, project, window)
        if item is None:
            cur += 1
            continue
        print(f"\n[review {cur + 1}/{len(filtered)}] [current label: {row['label']}] "
              f"{row['run_id']} {row['suite']} L{row['line_number']} "
              f"fp={row['fingerprint']}")
        print_context(item["lines"], item["line"], args.context_above,
                      args.context_below)
        k = get_key()
        if k in LABELS:
            row["label"] = LABELS[k]
            row["labeled_at"] = datetime.now(timezone.utc).isoformat()
            store.save_csv(path, rows)
            print(f"  -> changed to {LABELS[k]}")
            cur += 1
        elif k == "s":
            cur += 1
        elif k in ("q", "ESC"):
            break
    if con is not None:
        con.executemany(
            "INSERT OR REPLACE INTO labels VALUES (?,?,?,?,?)",
            [(("min" if window == 2 else "max"), r["fingerprint"], r["label"],
              r["labeled_at"], r["auto_rule_id"]) for r in rows if r["label"]],
        )
        con.commit()


def do_auto_classify(project, window, con):
    path = paths.csv_path(project, window)
    rows = store.load_csv(path)
    rules = config.load_auto_rules(project)
    applied = 0
    for row in rows:
        if row.get("label"):
            continue
        lines = detect.iter_log_lines(project, row["run_id"])
        if lines is None:
            continue
        res = match_auto_rule(lines, int(row["line_number"]), rules)
        if res is None:
            continue
        lab, rid = res
        row["label"] = lab
        row["labeled_at"] = datetime.now(timezone.utc).isoformat()
        row["auto_rule_id"] = rid
        applied += 1
    store.save_csv(path, rows)
    if con is not None:
        con.executemany(
            "INSERT OR REPLACE INTO labels VALUES (?,?,?,?,?)",
            [(("min" if window == 2 else "max"), r["fingerprint"], r["label"],
              r["labeled_at"], r["auto_rule_id"]) for r in rows if r["label"]],
        )
        con.commit()
    print(f"auto-classified {applied} fingerprints "
          f"(window={'min' if window == 2 else 'max'})")
    metrics.do_progress(project, con, window)


def do_report_env(project, window, args, con):
    rows = store.load_csv(paths.csv_path(project, window))
    shown = 0
    for row in rows:
        lines = detect.iter_log_lines(project, row["run_id"])
        if lines is None:
            continue
        ln = int(row["line_number"])
        hits = env_signals(lines[max(0, ln - 5):ln + 40])
        if not hits:
            continue
        print(f"[{row['run_id']}] {row['suite']} L{ln} "
              f"label={row.get('label') or 'unlabeled'} n_runs={row['n_runs']} "
              f"env={{{', '.join(hits)}}} :: {row['keyword'][:80]}")
        shown += 1
    print(f"\nenv-signal fingerprints shown: {shown}")

#!/usr/bin/env python3
"""Retro-validate existing coverage runs for "the runner behaved unexpectedly".

Scans projects/<name>/output/ for runs whose recorded coverage is unusable as
the study's exposure variable, and reports each problem run with a reason:

  zero_test_run   the suite's log reports it ran ZERO tests (vitest "no tests",
                  jest "Tests: 0 total", mocha "0 passing"), yet find-and-move-lcov.sh
                  recorded an all-zero lcov.info that passed structural validation.
  zero_hit_lcov   the lcov.info lists source files (LF > 0) but records zero
                  executed lines (LH == 0) — a strong silent-failure signal even
                  when the runner count cannot be recovered from the log.
  empty_lcov      the lcov.info has no SF: records at all.
  missing_log     only reported with --require-log; the matching logs/<ts>_<hash>.log
                  is absent, so a zero-test condition can neither be confirmed
                  nor ruled out.

This is the host-side counterpart to the in-container helper
helper/assert-suite-ran.sh: it lets you re-classify runs collected *before* that
guard was wired in, so stale all-zero lcov files can be located and deleted
before a re-run (collect_coverage.py skips commits that already have a .lcov).

Usage:
    python check_validity.py <project_name> [--output-dir <dir>] [--json PATH]
                             [--require-log] [--quiet]

Exit status:
    0   no problem runs found
    1   at least one problem run found
    2   usage / missing input error
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
PROJECTS_DIR = BASE_DIR / "projects"

# ── Runner summary patterns (mirror helper/assert-suite-ran.sh) ──────────────
ZERO_TEST_PATTERNS = [
    re.compile(r"^\s*Test Files\s+no tests", re.MULTILINE),
    re.compile(r"^\s*Test Files\s+0 passed \(0\)", re.MULTILINE),
    re.compile(r"^\s*Tests\s+no tests", re.MULTILINE),
    re.compile(r"^\s*Tests\s+0 passed \(0\)", re.MULTILINE),
    re.compile(r"Test Suites:\s+0 total", re.MULTILINE),
    re.compile(r"Tests:\s+0 total", re.MULTILINE),
    re.compile(r"(^|[^0-9])0 passing", re.MULTILINE),
]


def parse_lcov_counts(text: str) -> tuple[int, int]:
    """Return (LF, LH) summed over records, plus whether any SF: exists."""
    lf = lh = 0
    sf = 0
    for line in text.splitlines():
        if line.startswith("SF:"):
            sf += 1
        elif line.startswith("LF:"):
            try:
                lf += int(line.split(":", 1)[1])
            except ValueError:
                pass
        elif line.startswith("LH:"):
            try:
                lh += int(line.split(":", 1)[1])
            except ValueError:
                pass
    return sf, lf, lh


def zero_test_match(log_text: str) -> str | None:
    for pat in ZERO_TEST_PATTERNS:
        m = pat.search(log_text)
        if m:
            return m.group(0).strip()
    return None


def scan_project(proj_dir: Path, require_log: bool) -> list[dict]:
    output_dir = proj_dir / "output"
    logs_dir = proj_dir / "logs"
    if not output_dir.is_dir():
        print(f"Error: no output directory at {output_dir}", file=sys.stderr)
        sys.exit(2)

    problems: list[dict] = []
    for entry in sorted(output_dir.iterdir()):
        if not entry.is_dir():
            continue
        prefix = entry.name
        ts, _, commit_hash = prefix.partition("_")
        log_path = logs_dir / f"{prefix}.log"
        for lcov in sorted(entry.glob("*.lcov")):
            suite = lcov.stem
            text = lcov.read_text(errors="replace")
            sf, lf, lh = parse_lcov_counts(text)

            reasons: list[str] = []
            evidence = ""

            if sf == 0:
                reasons.append("empty_lcov")
            elif lf > 0 and lh == 0:
                reasons.append("zero_hit_lcov")

            log_text = ""
            if log_path.is_file():
                log_text = log_path.read_text(errors="replace")
                zt = zero_test_match(log_text)
                if zt:
                    reasons.append("zero_test_run")
                    evidence = zt
            elif require_log:
                reasons.append("missing_log")

            if reasons:
                problems.append(
                    {
                        "prefix": prefix,
                        "hash": commit_hash,
                        "timestamp": ts,
                        "suite": suite,
                        "suite_dir": str(lcov.parent.relative_to(output_dir)),
                        "lcov": str(lcov),
                        "reasons": reasons,
                        "lf": lf,
                        "lh": lh,
                        "evidence": evidence,
                    }
                )
    problems.sort(key=lambda p: p["prefix"], reverse=True)
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("project", help="project name under projects/")
    ap.add_argument(
        "--output-dir",
        help="output directory (default: projects/<name>/output/)",
    )
    ap.add_argument("--json", help="also write the problem list to this JSON path")
    ap.add_argument(
        "--require-log",
        action="store_true",
        help="report runs whose logs/<ts>_<hash>.log is missing",
    )
    ap.add_argument("--quiet", action="store_true", help="only print the summary")
    args = ap.parse_args()

    proj_dir = PROJECTS_DIR / args.project
    if args.output_dir:
        output_dir = Path(args.output_dir)
        proj_dir = output_dir.parent
    if not proj_dir.is_dir():
        print(f"Error: no project directory at {proj_dir}", file=sys.stderr)
        return 2

    problems = scan_project(proj_dir, args.require_log)

    total_runs = sum(1 for e in (proj_dir / "output").iterdir() if e.is_dir())
    bad_runs = len({p["prefix"] for p in problems})

    if not args.quiet:
        for p in problems:
            print(
                f"{p['prefix']}/{p['suite']}: {','.join(p['reasons'])} "
                f"(LF={p['lf']} LH={p['lh']})"
            )
            if p["evidence"]:
                print(f"    evidence: {p['evidence']}")

    print()
    print(f"project:  {args.project}")
    print(f"runs:     {total_runs}")
    print(f"problem runs: {bad_runs}")
    print(f"problem suites: {len(problems)}")
    reason_counts: dict[str, int] = {}
    for p in problems:
        for r in p["reasons"]:
            reason_counts[r] = reason_counts.get(r, 0) + 1
    for reason, n in sorted(reason_counts.items()):
        print(f"  - {reason}: {n}")

    if args.json:
        Path(args.json).write_text(json.dumps(problems, indent=2) + "\n")
        print(f"\nwrote {args.json}")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

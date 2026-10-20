#!/usr/bin/env python3
"""Automated failure labeler using TypeSafe AI's Jev (System 1 model).

Evaluates test failures from non-zero-exit runs to distinguish between:
  - study-acceptable:  genuine developer-facing code failures (assertions, bugs, mock issues)
  - study-problematic: environment / pipeline issues from the longitudinal replay runner
                       (missing bindings, ESM/CJS syntax, port collisions, OOM, build steps)

Operates independently from human labeling to produce an uncorrupted second opinion
and an actionable work-order / to-do report for fixing runner environments.

Usage:
  # Dry-run: preview extracted failures and sample prompt states
  ./check_failures_jev.py --project flowfuse --dry-run --limit 5

  # Run automated classification across a project (deduplicated by fingerprint)
  ./check_failures_jev.py --project flowfuse --concurrency 20

  # View aggregated pipeline issues / to-do report from existing labels
  ./check_failures_jev.py --project flowfuse --report
"""

import argparse
import asyncio
import csv
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set, Tuple
from dotenv import load_dotenv

load_dotenv()

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
SUITE_START_RE = re.compile(r"\[SUITE_START\]\s*(\S+)")
SUITE_END_RE = re.compile(r"\[SUITE_END\]\s*(\S+)")
TIMING_RE = re.compile(r"\(\d+(?:\.\d+)?\s*(?:s|ms)\)")
REPO_PREFIX_RE = re.compile(r"/coverage_reloaded/repo/?")
TIMESTAMP_RE = re.compile(r"\[\d{4}-\d{2}-\d{2}T[\d:\.]+Z?\]\s*")
LOC_NUM_RE = re.compile(r":\d+:\d+")
HEX_ADDR_RE = re.compile(r"\b0x[0-9a-fA-F]+\b")
UUID_RE = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.I)
REQ_ID_RE = re.compile(r'\"req-[a-z0-9]+\"', re.I)
STACK_AT_RE = re.compile(r"^\s*at\s+.*")
MOCHA_FAIL_HEADER_RE = re.compile(r"^\s*\d+\)\s+(.*)")
MOCHA_PASS_RE = re.compile(r"^\s*[✔√]")

ENV_PATTERNS = [
    re.compile(r"Cannot find module", re.I),
    re.compile(r"Cannot use import statement outside a module", re.I),
    re.compile(r"Test suite failed to run", re.I),
    re.compile(r"SyntaxError", re.I),
    re.compile(r"EADDRINUSE"),
    re.compile(r"gyp ERR"),
    re.compile(r"Killed|out of memory|\bOOM\b"),
    re.compile(r"webpack.*(?:Module build failed|Loader|Error)", re.I),
    re.compile(r"timed out|ETIMEDOUT|ECONNREFUSED|ENOTFOUND|EAI_AGAIN", re.I),
    re.compile(r"node-sass|node-gyp|Missing binding"),
]

DEFAULT_PATTERNS = [
    r"FAIL\s",
    r"✕",
    r"✗",
    r"●",
    r"\bAssertionError",
    r"Error:",
    r"\bfailed\b",
]

DEFAULT_EXCLUDES = [
    r"●\s*Console",
    r"Test Suites:",
    r"Tests:",
    r"Snapshots:",
]


def clean_ansi(line: str) -> str:
    return ANSI_RE.sub("", line).rstrip()


def normalize_line(line: str) -> str:
    s = ANSI_RE.sub("", line).strip()
    s = TIMING_RE.sub("", s)
    s = TIMESTAMP_RE.sub("", s)
    s = LOC_NUM_RE.sub("", s)
    s = HEX_ADDR_RE.sub("", s)
    s = UUID_RE.sub("<UUID>", s)
    s = REQ_ID_RE.sub('"<REQ>"', s)
    s = REPO_PREFIX_RE.sub("", s)
    if s.startswith("src/"):
        s = s[4:]
    if STACK_AT_RE.match(s):
        s = "at <STACK>"
    return s.strip()


def env_signals(text_lines: List[str]) -> List[str]:
    hits = []
    for pat in ENV_PATTERNS:
        for ln in text_lines:
            m = pat.search(ln)
            if m:
                hits.append(m.group(0))
                break
    return hits


def load_pattern_config(project: str) -> Tuple[List[re.Pattern], List[re.Pattern]]:
    path = os.path.join(REPO_ROOT, "projects", project, "failure_patterns.json")
    if os.path.isfile(path):
        try:
            with open(path) as f:
                cfg = json.load(f)
            general = cfg.get("general", {})
            pats = [re.compile(p) for p in general.get("patterns", DEFAULT_PATTERNS)]
            excs = [re.compile(p) for p in general.get("exclude", DEFAULT_EXCLUDES)]
            return pats, excs
        except Exception as e:
            print(f"[warn] Failed to parse failure_patterns.json: {e}", file=sys.stderr)

    return [re.compile(p) for p in DEFAULT_PATTERNS], [
        re.compile(p) for p in DEFAULT_EXCLUDES
    ]


def find_suite_span(lines: List[str], stem: str) -> Optional[Tuple[int, int, str]]:
    starts, ends = [], []
    for i, ln in enumerate(lines, 1):
        m = SUITE_START_RE.search(ln)
        if m:
            starts.append((m.group(1), i))
        m = SUITE_END_RE.search(ln)
        if m:
            ends.append((m.group(1), i))

    spans = []
    for name, s in starts:
        e = next((e_i for n, e_i in ends if n == name and e_i > s), None)
        if e:
            spans.append((name, s, e))

    if not spans:
        return None

    for name, s, e in spans:
        if name == stem:
            return (s, e, name)
    for name, s, e in spans:
        if (
            stem == name
            or stem.endswith("_" + name)
            or stem.startswith(name + "_")
            or name in stem
        ):
            return (s, e, name)
    return spans[0][1], spans[0][2], spans[0][0]


def fingerprint(fail_line: int, lines: List[str], window: int = 5) -> str:
    lo = max(0, fail_line - 1 - 4)
    hi = fail_line - 1 + window + 4
    blk = [normalize_line(ln) for ln in lines[lo : hi + 1]]

    for s in blk:
        if "✕" in s:
            name = s.split("✕", 1)[1].strip()
            if name:
                return hashlib.sha1(
                    ("test:" + name).encode("utf-8", "replace")
                ).hexdigest()[:16]
    for s in blk:
        if "●" in s and "›" in s:
            name = s.split("›", 1)[1].strip()
            if name:
                return hashlib.sha1(
                    ("test:" + name).encode("utf-8", "replace")
                ).hexdigest()[:16]
    for s in blk:
        if s.startswith("FAIL"):
            path = s[4:].strip()
            if path:
                return hashlib.sha1(
                    ("file:" + path).encode("utf-8", "replace")
                ).hexdigest()[:16]
    for s in blk:
        m = MOCHA_FAIL_HEADER_RE.match(s)
        if m:
            name = m.group(1).strip()
            if name:
                return hashlib.sha1(
                    ("test:" + name).encode("utf-8", "replace")
                ).hexdigest()[:16]

    block = "\n".join(
        normalize_line(ln) for ln in lines[fail_line - 1 : fail_line - 1 + window]
    )
    return hashlib.sha1(("blk:" + block).encode("utf-8", "replace")).hexdigest()[:16]


def collect_failures_for_run(
    project: str,
    run_dir: str,
    patterns: List[re.Pattern],
    excludes: List[re.Pattern],
    min_gap: int = 5,
    suite_filter: Optional[str] = None,
) -> List[Dict[str, Any]]:
    out_root = os.path.join(REPO_ROOT, "projects", project, "output")
    run_path = os.path.join(out_root, run_dir)
    if not os.path.isdir(run_path):
        return []

    log_path = os.path.join(REPO_ROOT, "projects", project, "logs", run_dir + ".log")
    if not os.path.isfile(log_path):
        return []

    with open(log_path, errors="replace") as f:
        lines = f.read().split("\n")

    results = []
    for ec_file in sorted(os.listdir(run_path)):
        if not ec_file.endswith(".exit_code"):
            continue
        stem = ec_file[: -len(".exit_code")]
        try:
            with open(os.path.join(run_path, ec_file)) as f:
                code = int(f.read().strip())
        except ValueError:
            continue
        if code <= 0:
            continue

        span = find_suite_span(lines, stem)
        if not span:
            continue
        if suite_filter and suite_filter not in span[2]:
            continue

        start, end, suite_name = span
        hits = []
        for i in range(start, end + 1):
            text = clean_ansi(lines[i - 1])
            if MOCHA_PASS_RE.search(text):
                continue
            if any(p.search(text) for p in excludes):
                continue
            if any(p.search(text) for p in patterns):
                hits.append((i, text))

        last = -(10**9)
        for ln, text in hits:
            if ln - last > min_gap:
                fp = fingerprint(ln, lines)
                results.append(
                    {
                        "project": project,
                        "run_id": run_dir,
                        "suite": suite_name,
                        "exit_code": code,
                        "line": ln,
                        "text": text,
                        "span": span,
                        "lines": lines,
                        "fp": fp,
                    }
                )
                last = ln

    return results


def iter_all_failures(
    project: str, suite_filter: Optional[str] = None, dedup: str = "project"
) -> List[Dict[str, Any]]:
    out_root = os.path.join(REPO_ROOT, "projects", project, "output")
    if not os.path.isdir(out_root):
        print(f"[error] Output directory not found: {out_root}", file=sys.stderr)
        return []

    patterns, excludes = load_pattern_config(project)
    run_dirs = sorted(os.listdir(out_root))

    all_failures = []
    fp_runs: Dict[str, Set[str]] = {}

    for run_dir in run_dirs:
        failures = collect_failures_for_run(
            project, run_dir, patterns, excludes, suite_filter=suite_filter
        )
        for f in failures:
            fp_runs.setdefault(f["fp"], set()).add(run_dir)
        all_failures.extend(failures)

    # Deduplication
    seen = set()
    deduped = []
    for f in all_failures:
        if dedup == "project":
            if f["fp"] in seen:
                continue
            seen.add(f["fp"])
            f["occurrences"] = len(fp_runs[f["fp"]])
        else:
            f["occurrences"] = 1
        deduped.append(f)

    return deduped


def build_state_for_item(
    item: Dict[str, Any], c_above: int = 4, c_below: int = 35
) -> Dict[str, Any]:
    lines = item["lines"]
    start, end, suite_name = item["span"]
    fail_line = item["line"]
    lo = max(start, fail_line - c_above)
    hi = min(end, fail_line + c_below)

    snippet_lines = []
    for i in range(lo, hi + 1):
        prefix = "▶ " if i == fail_line else "  "
        snippet_lines.append(f"{prefix}{i:5}: {clean_ansi(lines[i - 1])}")

    snippet = "\n".join(snippet_lines)
    env_hits = env_signals(lines[lo - 1 : hi])

    return {
        "project": item["project"],
        "suite": suite_name,
        "exit_code": item["exit_code"],
        "trigger_line": item["text"],
        "env_indicators": ", ".join(env_hits) if env_hits else "none",
        "log_snippet": snippet,
        "context": (
            "Longitudinal study test runner replaying historic commits (2021-2026). "
            "Tests are run in automated Linux containers."
        ),
    }


def get_jev_questions_dict() -> Dict[str, Any]:
    """JSON-serializable schema representation for Eden AI and HTTP clients."""
    return {
        "is_pipeline_issue": {
            "type": "noul",
            "instructions": (
                "Is this failure caused by a pipeline/environment setup problem rather than a genuine developer-facing test failure?\n"
                "- TRUE (study-problematic): Caused by our execution environment (e.g., missing system libraries, "
                "uninstalled Node modules, node-gyp build errors, missing native bindings, port collisions like EADDRINUSE, "
                "network timeouts to local services, Node engine/ESM syntax incompatibilities, out-of-memory kills).\n"
                "- FALSE (study-acceptable): A legitimate application or test logic failure that the original developers "
                "would have observed in their CI or local workstation (e.g., broken assertions, mock mismatches, "
                "expected vs. received diffs, unhandled exceptions inside the application code under test)."
            ),
        },
        "env_subsystem": {
            "type": "choice",
            "instructions": "If this is a pipeline issue, which subsystem needs to be fixed in our runner/Dockerfile?",
            "criteria": {
                "none": "Not a pipeline issue; genuine application/test failure.",
                "native_build_gyp": "node-gyp rebuild failed, missing Python, C++ headers, or native binary bindings.",
                "module_resolution": "Cannot find module, missing npm/yarn package in node_modules.",
                "node_runtime_syntax": "SyntaxError due to Node version mismatch (e.g., ESM import/export, optional chaining).",
                "ports_and_networking": "EADDRINUSE, ECONNREFUSED, port conflicts, localhost connection refused.",
                "memory_exhaustion": "JavaScript heap out of memory, process killed, SIGKILL.",
                "missing_build_step": "Missing build/ or dist/ directory, missing pre-test compilation.",
                "runner_env_config": "Test runner environment misconfigured (e.g., missing JSDOM/browser DOM globals in Node test environment, missing jest.config testEnvironment, or runner version mismatch).",
                "false_positive": "Not a failure; informational console log or summary table captured by regex.",
            },
        },
    }


def get_jev_questions_sdk():
    """Build the Jev schema questions using typesafe_sdk (for direct TypeSafe AI)."""
    try:
        from typesafe_sdk import Choice, Noul
    except ImportError:
        print(
            "[error] typesafe-sdk is not installed. Please install it with:\n"
            "        pip install typesafe-sdk",
            file=sys.stderr,
        )
        sys.exit(1)

    q = get_jev_questions_dict()
    return {
        "is_pipeline_issue": Noul(instructions=q["is_pipeline_issue"]["instructions"]),
        "env_subsystem": Choice(
            instructions=q["env_subsystem"]["instructions"],
            criteria=q["env_subsystem"]["criteria"],
        ),
    }


import urllib.request
import urllib.error


import time
import random

def call_edenai_decisions_sync(
    api_key: str,
    state: Dict[str, Any],
    questions: Dict[str, Any],
    model: str = "typesafe/jev-latest",
    max_retries: int = 5,
) -> Tuple[bool, float, str]:
    """Execute a decision query via Eden AI's /v3/alpha/decisions endpoint with retry on 429."""
    url = "https://api.edenai.run/v3/alpha/decisions"
    payload = {"model": model, "state": state, "questions": questions}
    data_bytes = json.dumps(payload).encode("utf-8")

    last_err = None
    for attempt in range(max_retries):
        req = urllib.request.Request(
            url,
            data=data_bytes,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "User-Agent": "cdbs-coverage-reloaded/1.0",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=35) as resp:
                res_data = json.loads(resp.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            last_err = e
            if e.code == 429 and attempt < max_retries - 1:
                # Parse "Retry after X seconds" or use exponential backoff with jitter
                m = re.search(r"Retry after (\d+(?:\.\d+)?) seconds", body)
                if m:
                    wait_time = float(m.group(1)) + random.uniform(0.3, 0.9)
                else:
                    wait_time = (1.5 ** attempt) + random.uniform(0.5, 1.2)
                time.sleep(wait_time)
                continue
            raise RuntimeError(f"Eden AI HTTP {e.code}: {body}") from e
    else:
        raise RuntimeError(f"Eden AI rate limit exceeded after {max_retries} retries: {last_err}")

    # Defensively parse the response structure from Eden AI / Jev
    answers = res_data.get("answers", res_data)
    noul_data = answers.get("is_pipeline_issue", {})
    choice_data = answers.get("env_subsystem", {})

    # Extract boolean noul:
    # Jev returns noul as a continuous probability float p in [0.0, 1.0] (probability condition is TRUE).
    # e.g., {"type": "noul", "noul": 0.13} -> 13% chance of pipeline issue -> False (87% confident acceptable)
    if isinstance(noul_data, dict):
        raw_val = noul_data.get("noul", noul_data.get("probability", noul_data.get("value", False)))
    else:
        raw_val = noul_data

    if isinstance(raw_val, (int, float)):
        prob_true = float(raw_val)
        is_issue = prob_true >= 0.5
        conf = prob_true if is_issue else (1.0 - prob_true)
    elif isinstance(raw_val, str):
        is_issue = raw_val.strip().lower() in ("true", "1", "yes")
        conf = 1.0
    else:
        is_issue = bool(raw_val)
        conf = 1.0

    # Extract choice
    if isinstance(choice_data, dict):
        subsystem = str(
            choice_data.get("choice", choice_data.get("value", "unspecified"))
        )
    else:
        subsystem = str(choice_data)

    return is_issue, conf, subsystem


def labels_csv_path(project: str) -> str:
    return os.path.join(REPO_ROOT, "projects", project, "failure_labels_jev.csv")


def load_existing_labels(project: str) -> Dict[str, Dict[str, Any]]:
    path = labels_csv_path(project)
    if not os.path.isfile(path):
        return {}
    results = {}
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for r in reader:
            fp = r.get("fingerprint")
            if fp:
                results[fp] = r
    return results


def save_labels(project: str, rows: List[Dict[str, Any]]):
    path = labels_csv_path(project)
    fieldnames = [
        "project",
        "run_id",
        "suite",
        "exit_code",
        "line_number",
        "fingerprint",
        "occurrences",
        "keyword",
        "is_pipeline_issue",
        "confidence",
        "env_subsystem",
        "labeled_at",
    ]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow(r)


async def classify_batch(
    project: str,
    provider: str,
    api_key: str,
    items: List[Dict[str, Any]],
    existing_by_fp: Dict[str, Dict[str, Any]],
    concurrency: int = 5,
    c_above: int = 4,
    c_below: int = 35,
) -> Dict[str, Dict[str, Any]]:
    sem = asyncio.Semaphore(concurrency)
    write_lock = asyncio.Lock()
    total = len(items)
    completed = 0
    all_by_fp = dict(existing_by_fp)

    if provider == "typesafe":
        try:
            from typesafe_sdk import AsyncTypeSafeClient
        except ImportError:
            print(
                "[error] typesafe-sdk is not installed. Run: pip install typesafe-sdk",
                file=sys.stderr,
            )
            sys.exit(1)
        client = AsyncTypeSafeClient()
        sdk_questions = get_jev_questions_sdk()
    else:
        edenai_questions = get_jev_questions_dict()

    async def _classify(it: Dict[str, Any], delay: float):
        nonlocal completed
        if delay > 0:
            await asyncio.sleep(delay)
        state = build_state_for_item(it, c_above, c_below)
        async with sem:
            try:
                if provider == "typesafe":
                    resp = await client.system_one(state=state, questions=sdk_questions)
                    noul_res = resp.nouls["is_pipeline_issue"]
                    choice_res = resp.choices["env_subsystem"]
                    is_issue = bool(noul_res.noul)
                    conf = getattr(
                        noul_res, "probability", getattr(noul_res, "score", 1.0)
                    )
                    subsystem = choice_res.choice
                else:
                    # Eden AI routed call via asyncio thread pool
                    is_issue, conf, subsystem = await asyncio.to_thread(
                        call_edenai_decisions_sync, api_key, state, edenai_questions
                    )

                row = {
                    "project": it["project"],
                    "run_id": it["run_id"],
                    "suite": it["suite"],
                    "exit_code": it["exit_code"],
                    "line_number": it["line"],
                    "fingerprint": it["fp"],
                    "occurrences": it.get("occurrences", 1),
                    "keyword": it["text"][:120],
                    "is_pipeline_issue": str(is_issue),
                    "confidence": f"{conf:.4f}",
                    "env_subsystem": subsystem,
                    "labeled_at": datetime.now(timezone.utc).isoformat(),
                }
                completed += 1
                status = (
                    "\033[91mPROBLEMATIC\033[0m"
                    if is_issue
                    else "\033[92mACCEPTABLE\033[0m"
                )
                print(
                    f"[{completed}/{total}] {it['run_id']} line {it['line']} -> {status} "
                    f"({conf*100:.1f}% | sub={subsystem})"
                )

                # Persist progressively to disk so interruptions (Ctrl-C) never lose progress
                async with write_lock:
                    all_by_fp[row["fingerprint"]] = row
                    save_labels(project, list(all_by_fp.values()))

                return row
            except Exception as e:
                print(
                    f"[error] Failed on {it['run_id']} line {it['line']}: {e}",
                    file=sys.stderr,
                )
                return None

    tasks = [_classify(it, idx * 0.15) for idx, it in enumerate(items)]
    try:
        await asyncio.gather(*tasks)
    except (KeyboardInterrupt, asyncio.CancelledError):
        print("\n[info] Interrupted. All progress so far has been saved to disk.")

    return all_by_fp


def print_report(project: str):
    path = labels_csv_path(project)
    if not os.path.isfile(path):
        print(f"No Jev labels found at {path}. Run without --report first.")
        return

    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))

    if not rows:
        print("Labels file is empty.")
        return

    total_fps = len(rows)
    total_occurrences = sum(int(r.get("occurrences", 1)) for r in rows)

    issues = [r for r in rows if r.get("is_pipeline_issue", "").lower() == "true"]
    acceptable = [r for r in rows if r.get("is_pipeline_issue", "").lower() == "false"]

    issues_occ = sum(int(r.get("occurrences", 1)) for r in issues)
    acc_occ = sum(int(r.get("occurrences", 1)) for r in acceptable)

    subsystems: Dict[str, List[Dict[str, Any]]] = {}
    for r in issues:
        sub = r.get("env_subsystem", "unspecified")
        subsystems.setdefault(sub, []).append(r)

    print("=" * 76)
    print(f" JEV PIPELINE HEALTH & TO-DO REPORT: {project.upper()}")
    print("=" * 76)
    print(
        f"Total Unique Signatures: {total_fps:,}  |  Total Failure Occurrences: {total_occurrences:,}"
    )
    print(
        f"  - Study-Acceptable (Dev Bugs): {len(acceptable):,} signatures ({acc_occ:,} runs / {acc_occ/max(1, total_occurrences)*100:.1f}%)"
    )
    print(
        f"  - Study-Problematic (Env Bugs): {len(issues):,} signatures ({issues_occ:,} runs / {issues_occ/max(1, total_occurrences)*100:.1f}%)"
    )
    print("-" * 76)
    print("ACTIONABLE PIPELINE TO-DOs (Grouped by Environment Subsystem):")
    print(f"{'Subsystem':<24} {'Unique':<8} {'Runs':<8} {'Sample Keyword'}")
    print("-" * 76)

    sorted_subs = sorted(
        subsystems.items(),
        key=lambda x: sum(int(r.get("occurrences", 1)) for r in x[1]),
        reverse=True,
    )
    for sub, items in sorted_subs:
        occ_sum = sum(int(r.get("occurrences", 1)) for r in items)
        sample = items[0].get("keyword", "")[:40]
        print(f"{sub:<24} {len(items):<8} {occ_sum:<8} {sample}")

    print("=" * 76)


BENCHMARK_CASES = [
    {
        "name": "Missing Playwright Browser (material-ui)",
        "expected": "PROBLEMATIC",
        "trigger": "Error: browserType.launch: Executable does not exist at /root/.cache/ms-playwright/chromium-1055/chrome-linux/chrome",
        "snippet": "Error: browserType.launch: Executable does not exist at /root/.cache/ms-playwright/chromium-1055/chrome-linux/chrome\n    Please run the following command to download new browsers:\n      npx playwright install",
        "env_hits": "Cannot find module",
    },
    {
        "name": "Node gyp build error (flowfuse)",
        "expected": "PROBLEMATIC",
        "trigger": "gyp ERR! build error",
        "snippet": "gyp ERR! build error\ngyp ERR! stack Error: Python executable \"/usr/bin/python\" is v3.8.10, which is not supported by gyp.\ngyp ERR! stack You must pass the --python switch to specify Python v2.7.\ngyp ERR! System Linux 5.15.0",
        "env_hits": "gyp ERR, node-gyp",
    },
    {
        "name": "Heap Out of Memory (flowfuse)",
        "expected": "PROBLEMATIC",
        "trigger": "<--- Last few GCs --->\nFATAL ERROR: Ineffective mark-compacts near heap limit Allocation failed - JavaScript heap out of memory",
        "snippet": "FATAL ERROR: Ineffective mark-compacts near heap limit Allocation failed - JavaScript heap out of memory\n 1: 0xb09c10 node::Abort() [node]\n 2: 0xa1c123 node::FatalError [node]",
        "env_hits": "JavaScript heap out of memory, Killed",
    },
    {
        "name": "EADDRINUSE Port Collision",
        "expected": "PROBLEMATIC",
        "trigger": "Error: listen EADDRINUSE: address already in use :::3000",
        "snippet": "events.js:292\n      throw er; // Unhandled 'error' event\n      ^\nError: listen EADDRINUSE: address already in use :::3000\n    at Server.setupListenHandle [as _listen2] (net.js:1318:16)",
        "env_hits": "EADDRINUSE",
    },
    {
        "name": "Missing GLIBC system library (flowfuse)",
        "expected": "PROBLEMATIC",
        "trigger": "Error: /lib/x86_64-linux-gnu/libc.so.6: version GLIBC_2.34 not found",
        "snippet": "Error: /lib/x86_64-linux-gnu/libc.so.6: version GLIBC_2.34 not found (required by node_modules/sqlite3/lib/binding/node-v93-linux-x64/node_sqlite3.node)\n    at Module._extensions..node (internal/modules/cjs/loader.js:1144:18)",
        "env_hits": "Missing binding",
    },
    {
        "name": "Assertion Error: expected vs received (apollo-client)",
        "expected": "ACCEPTABLE",
        "trigger": "AssertionError: expected undefined to exist",
        "snippet": "● EntityStore › gracefully handles eviction amid optimistic updates\n    AssertionError: expected undefined to exist\n        at Object.<anonymous> (packages/apollo-client/src/cache/__tests__/entityStore.ts:47:32)",
        "env_hits": "",
    },
    {
        "name": "Mock mismatch: spy called with wrong args",
        "expected": "ACCEPTABLE",
        "trigger": "Error: expect(jest.fn()).toHaveBeenCalledWith(...expected)",
        "snippet": "Error: expect(jest.fn()).toHaveBeenCalledWith(...expected)\n    Expected: \"user:123\"\n    Received: \"user:456\"\n        at Object.<anonymous> (test/unit/auth.test.js:82:14)",
        "env_hits": "",
    }
]


def run_self_test(provider: str, api_key: str):
    print("=" * 76)
    print(" RUNNING JEV VALIDATION BENCHMARK (Known Environment vs Acceptable Cases)")
    print("=" * 76)
    questions = get_jev_questions_dict()

    passed = 0
    total = len(BENCHMARK_CASES)

    for i, tc in enumerate(BENCHMARK_CASES, 1):
        state = {
            "project": "benchmark",
            "suite": "unit",
            "exit_code": 1,
            "trigger_line": tc["trigger"],
            "env_indicators": tc["env_hits"] or "none",
            "log_snippet": tc["snippet"],
            "context": "Longitudinal study test runner replaying historic commits. Automated Linux container execution."
        }
        is_issue, conf, sub = call_edenai_decisions_sync(api_key, state, questions)
        verdict = "PROBLEMATIC" if is_issue else "ACCEPTABLE"
        is_correct = (verdict == tc["expected"])
        if is_correct:
            passed += 1
            status_tag = "\033[92mPASS\033[0m"
        else:
            status_tag = "\033[91mFAIL\033[0m"

        print(f"[{i}/{total}] {status_tag} {tc['name']}")
        print(f"      Expected: {tc['expected']:<11} | Model Verdict: {verdict:<11} ({conf*100:.1f}%) | Subsystem: {sub}")

    print("-" * 76)
    accuracy = (passed / total) * 100
    color = "\033[92m" if passed == total else "\033[93m"
    print(f"Benchmark Results: {color}{passed}/{total} Passed ({accuracy:.1f}% Accuracy)\033[0m")
    print("=" * 76)


def parse_args():
    p = argparse.ArgumentParser(
        description="Jev-based automated failure classifier and to-do generator."
    )
    p.add_argument("--project", required=False, default=None, help="Project name inside projects/.")
    p.add_argument("--self-test", action="store_true", help="Run benchmark against known real environment vs acceptable fixtures.")
    p.add_argument(
        "--provider",
        type=str,
        default="auto",
        choices=["auto", "edenai", "typesafe"],
        help="Routing provider: 'edenai' (uses EDENAI_API_KEY) or 'typesafe' (uses TYPESAFE_API_KEY). Default: auto-detect.",
    )
    p.add_argument("--suite", type=str, default=None, help="Filter for specific suite.")
    p.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Limit number of unique failures to process.",
    )
    p.add_argument(
        "--concurrency",
        type=int,
        default=5,
        help="Max concurrent async requests to Jev (default: 5 to avoid 429 rate limits).",
    )
    p.add_argument(
        "--context-above", type=int, default=4, help="Context lines above failure line."
    )
    p.add_argument(
        "--context-below",
        type=int,
        default=35,
        help="Context lines below failure line.",
    )
    p.add_argument(
        "--dedup",
        type=str,
        default="project",
        choices=["project", "run"],
        help="Deduplicate by fingerprint across project (default) or per run.",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Print sample states without calling Jev API.",
    )
    p.add_argument(
        "--report",
        action="store_true",
        help="Print pipeline to-do report from existing CSV.",
    )
    p.add_argument(
        "--all",
        dest="only_unlabeled",
        action="store_false",
        default=True,
        help="Re-evaluate even previously labeled failures.",
    )
    return p.parse_args()


def main():
    args = parse_args()

    # Load .env if present
    env_file = os.path.join(REPO_ROOT, ".env")
    if os.path.isfile(env_file):
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip().strip("'\"")
                    if k and k not in os.environ:
                        os.environ[k] = v

    # Provider and API key resolution
    provider = args.provider
    eden_key = os.getenv("EDENAI_API_KEY")
    typesafe_key = os.getenv("TYPESAFE_API_KEY")

    if provider == "auto":
        if eden_key:
            provider = "edenai"
            api_key = eden_key
        elif typesafe_key:
            provider = "typesafe"
            api_key = typesafe_key
        else:
            print(
                "[error] Neither EDENAI_API_KEY nor TYPESAFE_API_KEY environment variable is set.\n"
                "        Set your key: export EDENAI_API_KEY='your-key' or export TYPESAFE_API_KEY='your-key'",
                file=sys.stderr,
            )
            sys.exit(1)
    elif provider == "edenai":
        if not eden_key:
            print("[error] EDENAI_API_KEY environment variable is not set.", file=sys.stderr)
            sys.exit(1)
        api_key = eden_key
    else:  # typesafe
        if not typesafe_key:
            print("[error] TYPESAFE_API_KEY environment variable is not set.", file=sys.stderr)
            sys.exit(1)
        api_key = typesafe_key

    if args.self_test:
        run_self_test(provider, api_key)
        return

    if not args.project:
        print("[error] --project is required (e.g. --project flowfuse) unless running --self-test", file=sys.stderr)
        sys.exit(1)

    if args.report:
        print_report(args.project)
        return

    failures = iter_all_failures(
        args.project, suite_filter=args.suite, dedup=args.dedup
    )
    if not failures:
        print(f"No failures found for project {args.project}.")
        return

    print(f"Found {len(failures):,} failures (dedup={args.dedup}) in {args.project}.")

    existing = load_existing_labels(args.project)
    if args.only_unlabeled and existing:
        to_process = [f for f in failures if f["fp"] not in existing]
        print(
            f"Skipping {len(failures) - len(to_process):,} already labeled. {len(to_process):,} remaining."
        )
    else:
        to_process = failures

    if args.limit:
        to_process = to_process[: args.limit]
        print(f"Limiting to first {len(to_process)} items.")

    if not to_process:
        print("Nothing left to process.")
        return

    if args.dry_run:
        print("\n--- [DRY RUN] Sample State ---")
        sample_state = build_state_for_item(
            to_process[0], args.context_above, args.context_below
        )
        print(
            json.dumps(
                {
                    "project": sample_state["project"],
                    "suite": sample_state["suite"],
                    "exit_code": sample_state["exit_code"],
                    "trigger_line": sample_state["trigger_line"],
                    "env_indicators": sample_state["env_indicators"],
                },
                indent=2,
            )
        )
        print("\nSample Log Snippet:\n" + sample_state["log_snippet"][:500] + "\n...")
        print("\nDry run completed. Omit --dry-run to send requests.")
        return

    print(f"\n[info] Using backend provider: {provider.upper()}")
    print(
        f"Starting Jev evaluation of {len(to_process)} failures with concurrency={args.concurrency}..."
    )

    all_by_fp = asyncio.run(
        classify_batch(
            project=args.project,
            provider=provider,
            api_key=api_key,
            items=to_process,
            existing_by_fp=existing,
            concurrency=args.concurrency,
            c_above=args.context_above,
            c_below=args.context_below,
        )
    )

    print(
        f"\nSaved {len(all_by_fp):,} total labels to {labels_csv_path(args.project)}."
    )

    # Print summary report
    print_report(args.project)


if __name__ == "__main__":
    main()

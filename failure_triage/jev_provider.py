"""Jev provider/prompt layer for v2 (self-contained).

Vendored from the v1 labeler (`check_failures_jev.py`, now archived at
`archive/v1_check_failures/` and untracked) so Jev v2 has no dependency on
the frozen v1 toolchain. This module owns:

- the environment-signal patterns (`env_signals`) fed to the model,
- the state building for one failure item (`build_state_for_item`),
- the Jev question schema for the SDK and HTTP/Eden AI clients,
- the Eden AI decisions call with 429 retry (`call_edenai_decisions_sync`),
- the validation benchmark (`run_self_test`).

Only detection input, output schema, confirmation and union reporting live
in `jev.py`; everything model-facing lives here.
"""

import json
import random
import re
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Dict, List, Tuple

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")

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


def clean_ansi(line: str) -> str:
    return ANSI_RE.sub("", line).rstrip()


def env_signals(text_lines: List[str]) -> List[str]:
    hits = []
    for pat in ENV_PATTERNS:
        for ln in text_lines:
            m = pat.search(ln)
            if m:
                hits.append(m.group(0))
                break
    return hits


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
    env_hits = env_signals(lines[lo - 1: hi])

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
    },
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

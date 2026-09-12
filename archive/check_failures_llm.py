#!/usr/bin/env python3
"""LLM-as-judge classifier for non-zero-exit test runs.

# ----------------------------------------------------------------------------
# QUICK START  (copy, edit <PORT>/<MODEL>, then run)
# ----------------------------------------------------------------------------
# Local script, remote LLM server (e.g. vLLM / Ollama / llama.cpp / litellm).
# Settings can be exported (see below) OR put in a .env file in this dir /
# the repo root (auto-loaded; shell env wins):
#
#   # .env
#   LLM_BASE_URL=http://132.231.141.24:<PORT>/v1
#   LLM_MODEL=<MODEL>            # e.g. qwen2.5-7b-instruct, llama3.1:8b
#   # OPENAI_API_KEY=...         # only if the remote server requires one
#
#   # 1) preview the prompts that would be sent (no API calls, no file writes)
#   python3 check_failures_llm.py --project apollo-client --dry-run --limit 3
#
#   # 2) run for real, capped at N API calls (re-runs resume via existing labels)
#   python3 check_failures_llm.py --project apollo-client --limit 50
#
# (Equivalent to the exports:)
#   export LLM_BASE_URL=http://132.231.141.24:<PORT>/v1
#   export LLM_MODEL=<MODEL>
#
# This tool writes its OWN artifacts (never the human tool's):
#   projects/<p>/failure_labels_llm.csv        (labels + confidence/judge/llm_reason)
#   projects/<p>/llm_judge_config.json         (this tool's config; auto_classify
#                                                seeds + rules the LLM learns)
#   projects/<p>/llm_judge_responses.log       (raw request/response audit trail)
# ----------------------------------------------------------------------------


A token-thrifty variant of check_failures.py. It reuses the same cheap, regex
driven failure detection (so NO whole logs are ever sent to a model) and layers
an OpenAI-compatible LLM on top to label the failures that regex cannot resolve.

Budget design:
  * Regex `auto_classify` rules (free) pre-filter every failure first.
  * Failures are deduplicated by fingerprint, so the LLM sees each UNIQUE
    signature once, not every re-print.
  * Only a small, configurable context window (lines above/below the trigger) is
    sent per failure.
  * The LLM ALSO proposes a `rule_body` for each labeled failure, which is
    committed back into the project's failure_patterns.json as a literal
    `auto_classify` rule. Future identical failures then match for free and never
    cost another API call -- the pipeline learns incrementally.

The LLM client speaks the OpenAI /chat/completions contract, so it works against
OpenAI, Azure, Together, Groq, local vLLM, or Ollama (OpenAI-compatible endpoint).

Labels (per study):
  acceptable      -> a genuine test failure devs of that era would also have seen
  problematic     -> an ENVIRONMENT issue in our pipeline that caused the failure
  unclear         -> ambiguous / could not decide
  false_positive  -> not a real failure (e.g. jest console-output capture)

Output is written to the same failure_labels.csv schema as check_failures.py
(plus `judge` and `llm_reason` columns), so the interactive tool can still
review/override later.
"""

import argparse
import csv
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

from check_failures import (
    REPO_ROOT,
    env_signals,
    fingerprint,
    iter_failures,
    match_auto_rule,
    normalize_line,
)

EXAMPLE_PROMPT = os.path.join(REPO_ROOT, "llm_judge_prompt.example.json")
DEFAULT_LLM_LABELS = ["acceptable", "problematic", "false_positive"]
CONFIDENCE_LEVELS = {"high", "medium", "low"}

# This tool keeps its artifacts SEPARATE from the human interactive classifier
# (check_failures.py -> failure_labels.csv / failure_patterns.json). The LLM judge
# writes failure_labels_llm.csv and learns into its OWN llm_judge_config.json
# (never the human failure_patterns.json).


def llm_labels_path(project, dedup):
    name = "failure_labels_llm.csv" if dedup == "run" else "failure_labels_llm_project.csv"
    return os.path.join(REPO_ROOT, "projects", project, name)


def load_existing_llm(project, dedup):
    """Read prior LLM labels (separate file from the human one) for resume."""
    path = llm_labels_path(project, dedup)
    rows = []
    if os.path.isfile(path):
        with open(path, newline="") as f:
            rows = list(csv.DictReader(f))
    for r in rows:
        r.setdefault("occurrences", "1")
        if not r.get("fingerprint"):
            log_path = os.path.join(REPO_ROOT, "projects", project, "logs", r["run_id"] + ".log")
            try:
                with open(log_path, errors="replace") as f:
                    lines = f.read().split("\n")
                r["fingerprint"] = fingerprint(int(r["line_number"]), lines)
            except (OSError, ValueError):
                r["fingerprint"] = ""
    if dedup == "project":
        done = {r["fingerprint"] for r in rows if r.get("fingerprint")}
    else:
        done = {(r["run_id"], r["fingerprint"]) for r in rows if r.get("fingerprint")}
    return path, rows, done


def llm_cfg_path(project):
    """This tool's OWN self-contained config: failure DETECTION (general/suites)
    AND its auto_classify rules (seed + learned). It never reads the human
    failure_patterns.json, keeping the two tools' concerns separated."""
    return os.path.join(REPO_ROOT, "projects", project, "llm_judge_config.json")


def load_llm_cfg(project):
    """Load the LLM tool's own config. Fails loudly if absent (no auto-seed)."""
    path = llm_cfg_path(project)
    if not os.path.isfile(path):
        sys.exit(
            f"[error] no llm_judge_config.json for project {project!r}\n"
            f"        copy llm_judge_config.example.json to "
            f"projects/{project}/llm_judge_config.json and tune it."
        )
    with open(path) as f:
        return json.load(f)


def load_auto_rules_llm(llm_cfg):
    """Free pre-filter rules: ONLY this tool's own auto_classify (3 LLM labels).
    The human failure_patterns.json is never consulted."""
    out = []
    for r in llm_cfg.get("auto_classify", []):
        m, label = r.get("match"), r.get("label")
        if m and label in DEFAULT_LLM_LABELS:
            # Force regex matching for every rule this tool owns.
            out.append((m, label, r.get("note", ""), int(r.get("lines", 5)), True))
    return out


def add_auto_rule_llm(project, body, label, note, lines):
    """Append a learned auto_classify rule to THIS tool's own config file."""
    path = llm_cfg_path(project)
    with open(path) as f:
        cfg = json.load(f)
    cfg.setdefault("auto_classify", [])
    cfg["auto_classify"].append({"match": body, "label": label, "note": note,
                                  "lines": lines, "regex": True})
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")


def render(template, mapping):
    """Safe {placeholder} substitution that ignores literal JSON braces."""
    out = template
    for k, v in mapping.items():
        out = out.replace("{" + k + "}", str(v))
    return out


def load_judge_prompt(args):
    """Resolve the prompt config: explicit --llm-prompt-file, else per-project
    override, else the shared example. CLI flags override the model name."""
    if args.llm_prompt_file:
        path = args.llm_prompt_file
    else:
        proj = os.path.join(REPO_ROOT, "projects", args.project, "llm_judge_prompt.json")
        path = proj if os.path.isfile(proj) else EXAMPLE_PROMPT
    if not os.path.isfile(path):
        sys.exit(f"[error] no judge prompt config at {path}")
    with open(path) as f:
        cfg = json.load(f)
    cfg["model"] = args.llm_model or cfg.get("model")
    return cfg, path


def build_window(it, above, below):
    """Normalized context window (above+below the trigger) shown to the LLM."""
    lines = it["lines"]
    start, end, _ = it["span"]
    trigger = it["line"]
    lo = max(start, trigger - above)
    hi = min(end, trigger + below)
    parts = []
    for i in range(lo, hi + 1):
        norm = normalize_line(lines[i - 1])
        marker = "▶ " if i == trigger else "  "
        parts.append(f"{marker}{norm}")
    return "\n".join(parts)


def build_region(it, below):
    """Normalized text BELOW the trigger that the committed rule will be matched
    against (mirrors match_auto_rule's scan region), used to validate rule_body."""
    lines = it["lines"]
    trigger = it["line"]
    region = max(12, below + 4)
    return "\n".join(normalize_line(l) for l in lines[trigger - 1: trigger - 1 + region])


def build_messages(it, window_text, env_hits, cfg, project):
    labels = cfg.get("labels", DEFAULT_LLM_LABELS)
    ld = cfg.get("label_definitions", {})
    ld_text = "\n".join(f"{k}: {v}" for k, v in ld.items()) or ", ".join(labels)
    user = render(cfg["user_template"], {
        "project": project,
        "suite": it["suite"],
        "exit_code": it["exit_code"],
        "env_signals": ", ".join(env_hits) if env_hits else "none",
        "failure_text": window_text,
        "labels": ", ".join(labels),
        "label_definitions": ld_text,
    })
    return [
        {"role": "system", "content": cfg.get("system", "")},
        {"role": "user", "content": user},
    ]


def call_llm(messages, cfg, args):
    """POST to an OpenAI-compatible /chat/completions endpoint. Returns the
    assistant content string, or None on hard failure (never raises)."""
    url = args.llm_base_url.rstrip("/") + "/chat/completions"
    body = {
        "model": cfg.get("model"),
        "messages": messages,
        "temperature": args.llm_temperature,
        "max_tokens": args.llm_max_tokens,
    }
    if cfg.get("json_mode", True):
        body["response_format"] = {"type": "json_object"}

    def post(payload):
        data = json.dumps(payload).encode()
        headers = {"Content-Type": "application/json"}
        if args.llm_api_key:
            headers["Authorization"] = f"Bearer {args.llm_api_key}"
        req = urllib.request.Request(url, data=data, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=args.llm_timeout) as resp:
            return json.loads(resp.read().decode())

    try:
        payload = post(body)
    except urllib.error.HTTPError as e:
        # Some endpoints reject response_format; retry once without it.
        if e.code == 400 and cfg.get("json_mode", True):
            body.pop("response_format", None)
            try:
                payload = post(body)
            except Exception as e2:
                print(f"[error] LLM call failed: {e2}", file=sys.stderr)
                return None
        else:
            print(f"[error] LLM HTTP {e.code}: {e.read().decode()[:300]}", file=sys.stderr)
            return None
    except Exception as e:
        print(f"[error] LLM call failed: {e}", file=sys.stderr)
        return None

    try:
        return payload["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        print(f"[error] unexpected LLM payload: {str(payload)[:200]}", file=sys.stderr)
        return None


def extract_json(text):
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        pass
    m = re.search(r"\{.*\}", text, re.S)
    if m:
        try:
            return json.loads(m.group(0))
        except (ValueError, TypeError):
            pass
    return None


def parse_response(content, cfg):
    """Return (label, reason, rule_body, confidence).

    Invalid/missing label defaults to 'problematic' (the conservative choice:
    exclude our own environment noise rather than risk false signal), with
    confidence forced to 'low'. Confidence outside {high,medium,low} -> 'low'.
    """
    labels = cfg.get("labels", DEFAULT_LLM_LABELS)
    if not content:
        # Defensive: callers must skip on None. Never fabricate a label here.
        return None, "no response", None, None
    data = extract_json(content)
    if not isinstance(data, dict):
        return "problematic", "unparseable response", None, "low"

    label = data.get("label")
    if label not in labels:
        label = "problematic"
        conf = "low"
    else:
        conf = data.get("confidence")
        if conf not in CONFIDENCE_LEVELS:
            conf = "low"

    reason = str(data.get("reason", ""))
    rule_body = data.get("rule_body")
    if rule_body is not None and not isinstance(rule_body, str):
        rule_body = None
    return label, reason, rule_body, conf


CSV_COLS = [
    "project", "run_id", "suite", "exit_code", "failure_index",
    "line_number", "keyword", "label", "confidence", "labeled_at", "fingerprint",
    "occurrences", "judge", "llm_reason",
]


def make_row(it, label, judge, reason, project, confidence="n/a"):
    return {
        "project": project,
        "run_id": it["run_id"],
        "suite": it["suite"],
        "exit_code": it["exit_code"],
        "failure_index": it["failure_index"],
        "line_number": it["line"],
        "keyword": it["text"],
        "label": label,
        "confidence": confidence,
        "labeled_at": datetime.now(timezone.utc).isoformat(),
        "fingerprint": it["fp"],
        "occurrences": it["occurrences"],
        "judge": judge,
        "llm_reason": reason,
    }


def flush(path, rows):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CSV_COLS)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def do_llm_judge(args, out_root, csv_path, existing_rows, cfg, dedup, resp_log, llm_cfg):
    rules = load_auto_rules_llm(llm_cfg)
    stored_matches = {m for (m, _label, _note, _n, _re) in rules}

    def keyfn(it):
        return it["fp"] if dedup == "project" else (it["run_id"], it["fp"])

    def row_key(r):
        return r["fingerprint"] if dedup == "project" else (r["run_id"], r["fingerprint"])

    done = {row_key(r) for r in existing_rows}
    current = {row_key(r): dict(r) for r in existing_rows}

    failures = list(iter_failures(args.project, out_root, args.min_gap,
                                  args.suite, args.fp_window, dedup, cfg=llm_cfg))

    processed = llmd = ruled = skipped = 0
    for it in failures:
        key = keyfn(it)
        if args.only_unlabeled and key in done:
            skipped += 1
            continue

        # Free regex pre-filter -- already known failures never hit the API.
        pre = match_auto_rule(it, rules)
        if pre is not None:
            current[key] = make_row(it, pre, "rule", "", args.project, confidence="n/a")
            done.add(key)
            flush(csv_path, list(current.values()))
            ruled += 1
            print(f"  rule:{pre}  L{it['line']}  {it['text'][:60]}")
            continue

        if args.limit and processed >= args.limit:
            break

        window = build_window(it, args.llm_context_above, args.llm_context_below)
        env_hits = env_signals(window.split("\n"))
        msgs = build_messages(it, window, env_hits, cfg, args.project)

        if args.dry_run:
            print("=" * 72)
            print(f"PROMPT  {it['run_id']} {it['suite']} L{it['line']} fp={it['fp']}")
            for m in msgs:
                print(f"[{m['role']}]\n{m['content']}\n")
            processed += 1
            continue

        content = call_llm(msgs, cfg, args)
        processed += 1

        # A failed call MUST NOT produce a label. Stop immediately -- if one
        # call fails (e.g. endpoint down) they all will, so retrying the rest
        # just spams an unavailable URL.
        if content is None:
            print(f"  llm:ERROR  L{it['line']}  LLM call failed", file=sys.stderr)
            print(f"[error] LLM endpoint failed. Stopping now -- fix the "
                  f"endpoint and re-run; unlabeled failures will be retried.",
                  file=sys.stderr)
            sys.exit(1)

        label, reason, rule_body, confidence = parse_response(content, cfg)
        stored_rule = False

        # Incremental learning: commit the model's regex pattern verbatim.
        # rule_body None/"" (model returned null: no good pattern) -> skip, no rule.
        # Guard against invalid regex so we never persist a dead rule.
        if rule_body and 0 < len(rule_body) <= 200 and rule_body not in stored_matches:
            try:
                re.compile(rule_body)
            except re.error:
                print(f"  llm:WARN  L{it['line']}  invalid regex, not stored: "
                      f"{rule_body!r}", file=sys.stderr)
            else:
                add_auto_rule_llm(args.project, rule_body, label, note=reason,
                                  lines=args.rule_lines)
                rules.append((rule_body, label, reason, args.rule_lines, True))
                stored_matches.add(rule_body)
                stored_rule = True

        current[key] = make_row(it, label, "llm", reason, args.project, confidence)
        done.add(key)
        flush(csv_path, list(current.values()))
        llmd += 1
        print(f"  llm:{label}  L{it['line']}  {reason[:60]}")

        if resp_log is not None:
            resp_log.write(json.dumps({
                "ts": datetime.now(timezone.utc).isoformat(),
                "run_id": it["run_id"], "suite": it["suite"], "line": it["line"],
                "fp": it["fp"], "request": msgs, "raw": content,
                "label": label, "confidence": confidence, "reason": reason,
                "rule_body": rule_body, "stored_rule": stored_rule,
            }) + "\n")
            resp_log.flush()

    if args.dry_run:
        print(f"dry-run done. prompts that would be sent={processed} "
              f"(rule-matched={ruled}, already-labeled skipped={skipped})")
        return
    print(f"done. llm_labeled={llmd} rule_matched={ruled} "
          f"skipped_done={skipped} prompts_sent={processed}")


def load_env_file(path):
    """Minimal .env loader (no external dep). Sets os.environ only for keys not
    already present, so real shell env wins over the file. Supports '#' comments
    and 'KEY="value"' / "KEY='value'" quoting."""
    if not path or not os.path.isfile(path):
        return
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            k, v = k.strip(), v.strip().strip('"').strip("'")
            os.environ.setdefault(k, v)


def parse_args():
    p = argparse.ArgumentParser(description="LLM-as-judge failure classifier.")
    p.add_argument("--project", required=True, help="Project name (must be in projects/).")
    p.add_argument("--llm-base-url", default=os.environ.get(
        "LLM_BASE_URL", "https://api.openai.com/v1"),
        help="OpenAI-compatible base URL (env LLM_BASE_URL).")
    p.add_argument("--llm-api-key", default=os.environ.get("OPENAI_API_KEY", ""),
        help="API key (env OPENAI_API_KEY).")
    p.add_argument("--llm-model", default=os.environ.get("LLM_MODEL"),
        help="Model name (env LLM_MODEL), else prompt config 'model'.")
    p.add_argument("--llm-prompt-file", default=None,
        help="Path to judge prompt JSON (default: projects/<p>/llm_judge_prompt.json else example).")
    p.add_argument("--llm-context-above", type=int, default=4,
        help="Lines ABOVE the trigger sent to the LLM (and used for rule matching).")
    p.add_argument("--llm-context-below", type=int, default=40,
        help="Lines BELOW the trigger sent to the LLM (the error body).")
    p.add_argument("--rule-lines", type=int, default=5,
        help="Scan window (lines below trigger) AND 'lines' stored for learned "
             "auto_classify rules. Decoupled from --llm-context-below.")
    p.add_argument("--llm-temperature", type=float, default=0.0,
        help="Sampling temperature (0 = deterministic).")
    p.add_argument("--llm-max-tokens", type=int, default=300,
        help="Max tokens in the LLM response.")
    p.add_argument("--llm-timeout", type=int, default=60,
        help="Per-call HTTP timeout (seconds).")
    p.add_argument("--limit", type=int, default=0,
        help="Cap API calls this run (0 = unlimited). Re-running resumes via existing labels.")
    p.add_argument("--min-gap", type=int, default=5,
        help="Only report a failure if >N lines after the previous one.")
    p.add_argument("--suite", type=str, default=None,
        help="Only process suites whose name contains this.")
    p.add_argument("--only-unlabeled", action="store_true", default=True,
        help="Skip failures already present in failure_labels.csv (default).")
    p.add_argument("--all", dest="only_unlabeled", action="store_false",
        help="Re-process even already-labeled failures (re-judges with the LLM).")
    p.add_argument("--fp-window", type=int, default=5,
        help="Normalized failure block size used to dedupe re-prints.")
    p.add_argument("--dedup", type=str, default="project", choices=["run", "project"],
        help="project: dedupe across all logs into failure_labels_llm_project.csv "
             "(one row per unique fingerprint, occurrences = # distinct runs sharing it, "
             "LLM called once per unique failure). run: one row per failure per log, "
             "occurrences always 1.")
    p.add_argument("--dry-run", action="store_true",
        help="Render and print each prompt; do not call the API or write labels.")
    p.add_argument("--env-file", default=None,
        help="Path to a .env file (also auto-loaded from ./ and the repo root).")
    return p.parse_args()


def _peek_env_file(argv):
    for i, a in enumerate(argv[1:], 1):
        if a == "--env-file" and i < len(argv):
            return argv[i]
        if a.startswith("--env-file="):
            return a.split("=", 1)[1]
    return None


def main():
    # Load .env (shell env still wins; then repo-root, then cwd, then --env-file).
    load_env_file(os.path.join(REPO_ROOT, ".env"))
    load_env_file(os.path.join(".", ".env"))
    ef = _peek_env_file(sys.argv)
    if ef:
        load_env_file(ef)

    args = parse_args()
    out_root = os.path.join(REPO_ROOT, "projects", args.project, "output")
    if not os.path.isdir(out_root):
        print(f"no output dir for project {args.project!r}", file=sys.stderr)
        sys.exit(1)

    cfg, prompt_path = load_judge_prompt(args)
    llm_cfg = load_llm_cfg(args.project)  # fails if absent; never auto-seeds
    csv_path, existing_rows, _done = load_existing_llm(args.project, args.dedup)
    resp_log_path = os.path.join(REPO_ROOT, "projects", args.project,
                                 "llm_judge_responses.log")
    resp_log = open(resp_log_path, "a") if not args.dry_run else None
    print(f"[info] prompt={prompt_path}  model={cfg.get('model')}  "
          f"ctx=({args.llm_context_above}+{args.llm_context_below})")
    print(f"[info] llm config={llm_cfg_path(args.project)} "
          f"(auto_classify seeds={len(llm_cfg.get('auto_classify', []))})")
    if resp_log:
        print(f"[info] raw LLM request/response log -> {resp_log_path}")
    try:
        do_llm_judge(args, out_root, csv_path, existing_rows, cfg, args.dedup,
                     resp_log, llm_cfg)
    finally:
        if resp_log:
            resp_log.close()


if __name__ == "__main__":
    main()

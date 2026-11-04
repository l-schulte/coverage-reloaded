"""Tier 0 normalization and text utilities.

Tier 0 is structural only (not semantic): ANSI, timing suffixes, the exact repo
prefix, blank-run collapsing and source coordinates. Tier 1/2 token rules are
intentionally not implemented here.
"""

import re

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
TIMING_PAREN_RE = re.compile(r"\(\d+(?:\.\d+)?\s*(?:s|ms)\)")
TIMING_END_RE = re.compile(r"\s+\d+(?:\.\d+)?\s*(?:ms|s)$")
REPO_PREFIX_RE = re.compile(r"/coverage_reloaded/repo/?")
SRC = r"[\w./@-]+\.(?:ts|tsx|js|jsx|mjs|cjs|vue|svelte|json)"
COORD1_RE = re.compile(r"(?P<p>" + SRC + r"):(?P<l>\d+):(?P<c>\d+)")
COORD2_RE = re.compile(r"(?P<p>" + SRC + r")\((?P<l>\d+),(?P<c>\d+)\)")

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


def clean(line):
    if "\x1b" in line:
        line = ANSI_RE.sub("", line)
    return line.rstrip()


def normalize_line(line, prefix_re=None):
    s = ANSI_RE.sub("", line)
    s = s.strip()
    if prefix_re is not None:
        s = prefix_re.sub("", s, count=1)
    if "(" in s:
        s = TIMING_PAREN_RE.sub("", s)
    if s.endswith(("s", "ms")):
        s = TIMING_END_RE.sub("", s)
    if "/coverage_reloaded/repo" in s:
        s = REPO_PREFIX_RE.sub("", s)
    if ":" in s:
        s = COORD1_RE.sub(lambda m: f"{m.group('p')}:<n>:<n>", s)
    if "(" in s:
        s = COORD2_RE.sub(lambda m: f"{m.group('p')}(<n>,<n>)", s)
    # Re-strip: removing a timing leaves trailing whitespace, and a line with
    # "(9.8s)" must hash identically to the same line without it.
    return s.strip()


def collapse_blanks(norm_lines):
    out = []
    for l in norm_lines:
        if l == "" and out and out[-1] == "":
            continue
        out.append(l)
    while out and out[-1] == "":
        out.pop()
    return out


def env_signals(text_lines):
    hits = []
    for pat in ENV_PATTERNS:
        for ln in text_lines:
            m = pat.search(ln)
            if m:
                hits.append(m.group(0))
                break
    return hits

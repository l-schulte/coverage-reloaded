"""LCOV parsing and suite aggregation."""


# ── LCOV parser ──────────────────────────────────────────────────────────────


def parse_lcov(text: str) -> dict:
    lines = lines_hit = 0
    functions = functions_hit = 0
    branches = branches_hit = 0

    for line in text.splitlines():
        if line.startswith("DA:"):
            parts = line.split(",")
            if len(parts) == 2:
                lines += 1
                try:
                    if int(parts[1]) > 0:
                        lines_hit += 1
                except ValueError:
                    pass
        elif line.startswith("FNF:"):
            try:
                functions += int(line.split(":")[1])
            except ValueError:
                pass
        elif line.startswith("FNH:"):
            try:
                functions_hit += int(line.split(":")[1])
            except ValueError:
                pass
        elif line.startswith("BRF:"):
            try:
                branches += int(line.split(":")[1])
            except ValueError:
                pass
        elif line.startswith("BRH:"):
            try:
                branches_hit += int(line.split(":")[1])
            except ValueError:
                pass

    def pct(hit, total):
        return round(hit / total * 100, 1) if total > 0 else None

    return {
        "lines": {"hit": lines_hit, "total": lines, "pct": pct(lines_hit, lines)},
        "functions": {
            "hit": functions_hit,
            "total": functions,
            "pct": pct(functions_hit, functions),
        },
        "branches": {
            "hit": branches_hit,
            "total": branches,
            "pct": pct(branches_hit, branches),
        },
    }


def aggregate_suites(suites: list) -> dict | None:
    lh = lt = fh = ft = bh = bt = 0
    for s in suites:
        cov = s.get("coverage")
        if not cov:
            continue
        lh += cov["lines"]["hit"]
        lt += cov["lines"]["total"]
        fh += cov["functions"]["hit"]
        ft += cov["functions"]["total"]
        bh += cov["branches"]["hit"]
        bt += cov["branches"]["total"]
    if lt == 0 and ft == 0 and bt == 0:
        return None
    pct = lambda h, t: round(h / t * 100, 1) if t > 0 else None
    return {
        "lines": {"hit": lh, "total": lt, "pct": pct(lh, lt)},
        "functions": {"hit": fh, "total": ft, "pct": pct(fh, ft)},
        "branches": {"hit": bh, "total": bt, "pct": pct(bh, bt)},
    }

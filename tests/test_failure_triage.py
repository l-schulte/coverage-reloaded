"""Unit tests for the v2 failure_triage package."""

import json

import pytest

from failure_triage import detect, metrics, normalize, paths, store
from failure_triage.fingerprint import compute_fingerprints


def test_normalize_tier0():
    raw = "\x1b[31mFAIL app/src/x.ts (9.806s)\x1b[0m"
    assert normalize.normalize_line(raw) == "FAIL app/src/x.ts"
    assert (normalize.normalize_line("app/src/x.ts:12:34 - error TS1: bad")
            == "app/src/x.ts:<n>:<n> - error TS1: bad")
    # Tier 0 does not normalize volatile temp paths or numbers.
    assert normalize.normalize_line("lstat '/tmp/x-abc'") == "lstat '/tmp/x-abc'"
    assert normalize.normalize_line("Expected 2") == "Expected 2"


def test_fingerprint_windows_and_stability():
    lines = [
        "  ● suite › test",
        "",
        "    expected A",
        "",
        "    line 4",
        "    line 5",
        "    line 6",
    ]
    fp_min, fp_max, bmin, bmax = compute_fingerprints(lines, 1)
    assert bmin == "● suite › test\n\nexpected A"
    assert bmax.startswith(bmin)
    # fp_max is trigger + 5 following lines = 6 lines; the 7th line is excluded.
    assert "line 5" in bmax and "line 6" not in bmax

    # Same first three lines, different extra lines -> same fp_min, different fp_max.
    lines2 = list(lines)
    lines2[4] = "    other line 4"
    fp_min2, fp_max2, _, _ = compute_fingerprints(lines2, 1)
    assert fp_min2 == fp_min
    assert fp_max2 != fp_max

    # A different error in the 3-line window -> different fp_min.
    lines3 = list(lines)
    lines3[2] = "    expected B"
    fp_min3, _, _, _ = compute_fingerprints(lines3, 1)
    assert fp_min3 != fp_min


def test_reprint_collapses():
    lines = [
        "  ● suite › test",
        "",
        "    expected A",
        "  ● suite › test",
        "",
        "    expected A",
    ]
    assert compute_fingerprints(lines, 1)[0] == compute_fingerprints(lines, 4)[0]


def _write_fixture(tmp_path, monkeypatch):
    monkeypatch.setattr(paths, "REPO_ROOT", str(tmp_path))
    proj = tmp_path / "projects" / "_t"
    (proj / "logs").mkdir(parents=True)
    (proj / "output" / "1000_abc").mkdir(parents=True)
    (proj / "output" / "1000_abc" / "unit.exit_code").write_text("1")
    (proj / "failure_patterns.json").write_text(json.dumps({
        "general": {"patterns": ["●"], "exclude": []},
        "min_gap": 5,
    }))
    (proj / "logs" / "1000_abc.log").write_text("\n".join([
        "[SUITE_START] unit",
        "FAIL a-test.ts",
        "  ● suite › one",
        "",
        "    expected A",
        "",
        "    at a",
        "",
        "  ● suite › two",
        "",
        "    expected B",
        "",
        "    at b",
        "[SUITE_END] unit",
    ]) + "\n")
    return proj


def test_select_span_fallback_order(tmp_path, monkeypatch):
    """A suite stem matching no [SUITE_START] name falls back to the first
    span in (start, end, name) order — not the stored (name, start, end)."""
    monkeypatch.setattr(paths, "REPO_ROOT", str(tmp_path))
    proj = tmp_path / "projects" / "_t"
    (proj / "logs").mkdir(parents=True)
    (proj / "output" / "1000_abc").mkdir(parents=True)
    (proj / "output" / "1000_abc" / "mystery.exit_code").write_text("1")
    (proj / "logs" / "1000_abc.log").write_text("\n".join([
        "[SUITE_START] unit",
        "  ● suite › one",
        "",
        "    expected A",
        "[SUITE_END] unit",
    ]) + "\n")
    cfg = {"general": {"patterns": ["●"], "exclude": []}, "min_gap": 5}
    families, failures, runs = detect.scan(
        "_t", cfg, str(proj / "output"), 5, None, [2],
    )
    assert len(failures) == 1
    assert failures[0]["suite"] == "mystery"
    assert families[2]


def test_scan_splits_distinct_errors(tmp_path, monkeypatch):
    proj = _write_fixture(tmp_path, monkeypatch)
    cfg = json.loads((proj / "failure_patterns.json").read_text())
    families, failures, runs = detect.scan(
        "_t", cfg, str(proj / "output"), 5, None, [2, 5],
    )
    assert len(failures) == 2
    assert len(families[2]) == 2          # two distinct errors
    assert len(families[5]) == 2
    assert runs == {"1000_abc": 1}
    for rec in families[2].values():
        assert rec["runs"] == {"1000_abc"}


def test_csv_roundtrip_multiline_block(tmp_path, monkeypatch):
    monkeypatch.setattr(paths, "REPO_ROOT", str(tmp_path))
    path = tmp_path / "labels.csv"
    rows = [{
        "project": "_t", "window": "min", "run_id": "1000_abc",
        "suite": "unit", "exit_code": "1", "line_number": "3",
        "keyword": "● suite › one", "label": "unclear", "labeled_at": "",
        "fingerprint": "abc", "n_runs": "1", "n_variants": "1",
        "example_variant_fp": "def", "auto_rule_id": "", "first_run": "1000_abc",
        "last_run": "1000_abc", "block": "line1\nline2\nline3",
    }]
    store.save_csv(str(path), rows)
    loaded = store.load_csv(str(path))
    assert loaded[0]["block"] == "line1\nline2\nline3"
    assert loaded[0]["label"] == "unclear"


def test_path_resolution_prefers_label_analysis(tmp_path, monkeypatch):
    monkeypatch.setattr(paths, "REPO_ROOT", str(tmp_path))
    proj = tmp_path / "projects" / "_t"
    proj.mkdir(parents=True)
    # Unmigrated project: everything at the project root.
    (proj / "failure_patterns.json").write_text("{}")
    assert paths.patterns_path("_t") == str(proj / "failure_patterns.json")
    assert paths.v1_labels_path("_t") == str(proj / "failure_labels_project.csv")
    # Migrated project: label_analysis (and its v1/) wins.
    (proj / "label_analysis" / "v1").mkdir(parents=True)
    (proj / "label_analysis" / "failure_patterns.json").write_text("{}")
    (proj / "label_analysis" / "v1" / "failure_labels_project.csv").write_text("x")
    assert (paths.patterns_path("_t")
            == str(proj / "label_analysis" / "failure_patterns.json"))
    assert (paths.v1_labels_path("_t")
            == str(proj / "label_analysis" / "v1" / "failure_labels_project.csv"))
    assert paths.csv_path("_t", 2).endswith(
        "label_analysis/failure_labels_project_min.csv")
    assert paths.db_path("_t").endswith("label_analysis/failure_labels_v2.db")


def test_crosscheck_writes_artifact(tmp_path, monkeypatch):
    monkeypatch.setattr(paths, "REPO_ROOT", str(tmp_path))
    proj = tmp_path / "projects" / "_t"
    la = proj / "label_analysis"
    v1dir = la / "v1"
    v1dir.mkdir(parents=True)
    # v1 reference: one row matches a v2 detection, one is unmatched.
    (v1dir / "failure_labels_project.csv").write_text(
        "project,run_id,suite,exit_code,failure_index,line_number,keyword,"
        "label,labeled_at,fingerprint,occurrences,auto_rule_id\n"
        "_t,1000_abc,unit,1,1,3,one,acceptable,,v1a,1,\n"
        "_t,1000_abc,unit,1,2,99,gone,problematic,,v1b,1,\n")
    store.save_csv(str(la / "failure_labels_project_min.csv"), [
        {"project": "_t", "window": "min", "run_id": "1000_abc",
         "suite": "unit", "line_number": "3", "keyword": "one",
         "label": "acceptable", "fingerprint": "f1",
         "first_run": "1000_abc", "last_run": "1000_abc", "block": "b1"},
        {"project": "_t", "window": "min", "run_id": "1000_abc",
         "suite": "unit", "line_number": "10", "keyword": "two",
         "label": "problematic", "fingerprint": "f2",
         "first_run": "1000_abc", "last_run": "1000_abc", "block": "b2"},
    ])
    store.save_csv(str(la / "failure_labels_project_max.csv"), [
        {"project": "_t", "window": "max", "run_id": "1000_abc",
         "suite": "unit", "line_number": "3", "keyword": "one",
         "label": "unclear", "fingerprint": "g1",
         "first_run": "1000_abc", "last_run": "1000_abc", "block": "b1x"},
    ])
    con = store.open_db(str(la / "failure_labels_v2.db"))
    store.write_db(con, [
        {"run_id": "1000_abc", "suite": "unit", "line": 3,
         "fp_min": "f1", "fp_max": "g1", "text": "one", "exit_code": 1},
        {"run_id": "1000_abc", "suite": "unit", "line": 10,
         "fp_min": "f2", "fp_max": "g2", "text": "two", "exit_code": 1},
    ], {"1000_abc": 1}, [])

    metrics.do_crosscheck("_t", con)

    art = (v1dir / "_t_v2_doublecheck.md").read_text()
    assert "matched v1 labeled rows: 1/2" in art
    assert "label conflicts within one v2 family: 0" in art
    assert "unmatched 1000_abc unit L99" in art
    assert "agree: 1, disagree: 0" in art
    assert "1 detection pairs labeled differently across windows" in art
    assert art.index("## Verdict") > 0

#!/usr/bin/env python3
"""Thin entrypoint for the v2 failure-triage toolchain.

The implementation lives in the `failure_triage` package:
  failure_triage/cli.py       argparse + dispatch
  failure_triage/config.py    failure_patterns.json / auto rules
  failure_triage/normalize.py Tier 0 normalization
  failure_triage/fingerprint.py fp_min (3 lines) / fp_max (6 lines)
  failure_triage/detect.py    suite spans, failure collection, scan
  failure_triage/store.py     CSVs + SQLite
  failure_triage/metrics.py   progress / stats / analyze / crosscheck
  failure_triage/label.py     interactive labeling / auto-classify / verify
"""

from failure_triage.cli import main

if __name__ == "__main__":
    main()

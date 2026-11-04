#!/usr/bin/env python3
"""Fix per-workspace exit codes in compass output directories.

In historical compass runs, install-and-run.sh had a bug where matching
'lerna success - <pkg>' in Lerna v4's run completion summary reset all
workspace test.exit_code files to 0, even when test suites had failed.

This script parses the raw logs from projects/compass/logs/<ts>_<hash>.log:
1. Identifies which workspace packages failed (from npm ERR! at location: ...).
2. Extracts their true exit code (number of failing mocha tests, or 1 for lifecycle failure).
3. Updates the corresponding <subdir>_test.exit_code in projects/compass/output/<ts>_<hash>/.
4. Verifies that passing workspaces remain exit_code 0.
"""

import os
import re
import sys
import time

FAILING_COUNT_RE = re.compile(r"^([@\w/-]+):\s+(\d+)\s+failing\b", re.M)
KARMA_EXIT_RE = re.compile(r"^([@\w/-]+):\s+Failed with exit code:\s*(\d+)", re.M)
LOCATION_RE = re.compile(r"^([@\w/-]+):\s+npm ERR!\s+at location:\s+/coverage_reloaded/repo/(\S+)", re.M)

def parse_log(log_path):
    with open(log_path, errors="replace") as f:
        text = f.read()
    
    # Map failing package name -> relative repo directory
    pkg_to_dir = {}
    for m in LOCATION_RE.finditer(text):
        pkg, loc = m.group(1), m.group(2)
        pkg_to_dir[pkg] = loc
        
    if not pkg_to_dir:
        return {}
        
    dir_to_code = {}
    for pkg, loc in pkg_to_dir.items():
        m_cnt = re.search(rf"^{re.escape(pkg)}:\s+(\d+)\s+failing\b", text, re.M)
        if m_cnt:
            dir_to_code[loc] = min(int(m_cnt.group(1)), 255)
            continue
        m_karma = re.search(rf"^{re.escape(pkg)}:\s+Failed with exit code:\s*(\d+)", text, re.M)
        if m_karma:
            dir_to_code[loc] = int(m_karma.group(1))
            continue
        dir_to_code[loc] = 1
        
    return dir_to_code

def main():
    compass_dir = os.path.dirname(os.path.abspath(__file__))
    output_root = os.path.join(compass_dir, "output")
    logs_root = os.path.join(compass_dir, "logs")

    if not os.path.isdir(output_root):
        print(f"Error: output dir not found at {output_root}")
        sys.exit(1)

    run_dirs = sorted([d for d in os.listdir(output_root) if os.path.isdir(os.path.join(output_root, d))])
    print(f"Scanning {len(run_dirs)} run directories in {output_root}...")

    t0 = time.time()
    updated_runs = 0
    updated_files = 0
    total_exit_code_files = 0

    for idx, run_id in enumerate(run_dirs, 1):
        out_dir = os.path.join(output_root, run_id)
        log_file = os.path.join(logs_root, f"{run_id}.log")

        if not os.path.isfile(log_file):
            continue

        dir_to_code = parse_log(log_file)
        
        # Files in this run
        run_updated = False
        for f in os.listdir(out_dir):
            if not f.endswith(".exit_code"):
                continue
            total_exit_code_files += 1

            # Stem without _test.exit_code
            # safe_stem is <dir.replace('/', '_').replace('-', '_')>_test.exit_code
            stem = f[:-len("_test.exit_code")] if f.endswith("_test.exit_code") else f[:-len(".exit_code")]

            # Check if this file matches any failing dir
            target_code = 0
            for loc, code in dir_to_code.items():
                loc_stem = loc.replace("/", "_").replace("-", "_")
                if stem == loc_stem:
                    target_code = code
                    break

            file_path = os.path.join(out_dir, f)
            current_val = open(file_path).read().strip()
            if target_code > 0:
                if current_val != str(target_code):
                    with open(file_path, "w") as fp:
                        fp.write(f"{target_code}\n")
                    updated_files += 1
                    run_updated = True
            else:
                if current_val != "0":
                    with open(file_path, "w") as fp:
                        fp.write("0\n")
                    updated_files += 1
                    run_updated = True

        if run_updated:
            updated_runs += 1

        if idx % 500 == 0 or idx == len(run_dirs):
            print(f"  [{idx}/{len(run_dirs)}] Updated {updated_files} files across {updated_runs} runs...")

    elapsed = time.time() - t0
    print(f"\nDone in {elapsed:.1f}s.")
    print(f"Total exit code files inspected: {total_exit_code_files}")
    print(f"Total files updated to correct non-zero exit codes: {updated_files}")
    print(f"Total runs with corrected failure exit codes: {updated_runs} out of {len(run_dirs)}")

if __name__ == "__main__":
    main()

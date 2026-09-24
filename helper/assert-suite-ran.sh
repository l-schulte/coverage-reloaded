#!/usr/bin/env bash
#
# assert-suite-ran.sh — Fail loudly when a test suite reported that it ran
# zero tests (a runner-produced number), i.e. the runner "behaved unexpectedly".
#
# SYNOPSIS
#   source /coverage_reloaded/logging.sh
#   source /coverage_reloaded/assert-suite-ran.sh
#   assert_suite_ran <suite> <runner> <log_file> [<exit_code>]
#
# DESCRIPTION
#   A suite that exits non-zero after running *no* tests is the most dangerous
#   failure mode for the study's exposure variable: the runner still emits a
#   structurally valid lcov.info (all files listed, every hit count zero) that
#   passes every structural check, so the commit is recorded as a successful
#   coverage run while measuring nothing.
#
#   This guard parses the runner's OWN reported test count from the suite log
#   and aborts the run (exit 1, under `set -e`) when that count is zero. It does
#   NOT flag a suite that ran tests and failed some of them — that is a normal,
#   visible partial result and must keep its (valid) coverage.
#
#   Only a runner-produced count is trusted. Generic markers such as Vitest's
#   "Unhandled Errors" are deliberately NOT used: they also appear on runs that
#   executed hundreds of tests successfully, so treating them as "zero tests"
#   would discard valid coverage.
#
#   Call this *after* the test command and *before* find-and-move-lcov.sh, so a
#   zero-test run never has its bogus lcov recorded.
#
# SUPPORTED RUNNERS (summary lines the runner prints to stdout)
#   vitest   "Test Files  no tests"      / "Test Files  0 passed (0)"
#            "Tests  no tests"           / "Tests  0 passed (0)"
#   jest     "Test Suites: 0 total"      / "Tests:       0 total"
#   mocha    "0 passing" (e.g. "0 passing (12ms)")
#   tap      "# tests 0" / "0 tests"
#
#   exit_code (optional 4th arg) is only used to make the failure message
#   explicit about a runner that exited 0 while running nothing.
#
# USAGE
#   set +e
#   fake_time yarn vitest run --coverage.enabled --coverage.reporter=lcov ...
#   VITEST_EXIT=$?
#   set -e
#   assert_suite_ran "vitest" "vitest" "$LOGFILE" "$VITEST_EXIT"
#   bash /coverage_reloaded/find-and-move-lcov.sh "vitest" "true" "$VITEST_EXIT"
#
# ENVIRONMENT
#   SUITE_RAN_STRICT  "0" downgrades a missing count to a warning (default "1":
#                     an unrecognised runner summary for a non-zero exit is a
#                     loud error, so a parser gap surfaces instead of silently
#                     passing).
#
# EXIT STATUS
#   0   the suite ran at least one test, or the count was unparseable but the
#       suite exited 0 (nothing to assert)
#   1   the suite reported zero tests, or (strict) a non-zero exit produced no
#       parseable count — the caller aborts via `set -e`
#   2   called without a log file (programming error)
#
assert_suite_ran() {
    local suite="${1:-}"
    local runner="${2:-}"
    local log_file="${3:-}"
    local exit_code="${4:-0}"

    if [ -z "$log_file" ]; then
        print_header 2 "ERROR: assert_suite_ran requires a log file path" "suite=$suite runner=$runner"
        exit 2
    fi
    if [ ! -f "$log_file" ]; then
        print_header 2 "ERROR: assert_suite_ran log file not found: $log_file" "suite=$suite runner=$runner"
        exit 2
    fi

    # verdict: "zero" (runner reported no tests), "ran" (runner reported a
    # positive test tally), or "" (no summary line recognisable for this runner).
    local verdict="" evidence=""

    case "$runner" in
        vitest)
            evidence=$(grep -m1 -E '^[[:space:]]*Test Files[[:space:]]+no tests' "$log_file" || true)
            if [ -n "$evidence" ]; then verdict="zero"; fi
            if [ -z "$verdict" ]; then
                evidence=$(grep -m1 -E '^[[:space:]]*Test Files[[:space:]]+0 passed \(0\)' "$log_file" || true)
                [ -n "$evidence" ] && verdict="zero"
            fi
            if [ -z "$verdict" ]; then
                evidence=$(grep -m1 -E '^[[:space:]]*Tests[[:space:]]+no tests' "$log_file" || true)
                [ -n "$evidence" ] && verdict="zero"
            fi
            if [ -z "$verdict" ]; then
                evidence=$(grep -m1 -E '^[[:space:]]*Tests[[:space:]]+0 passed \(0\)' "$log_file" || true)
                [ -n "$evidence" ] && verdict="zero"
            fi
            if [ -z "$verdict" ]; then
                evidence=$(grep -m1 -E '^[[:space:]]*Test Files[[:space:]]+[1-9][0-9]* (passed|failed)' "$log_file" || true)
                [ -n "$evidence" ] && verdict="ran"
            fi
            if [ -z "$verdict" ]; then
                evidence=$(grep -m1 -E '^[[:space:]]*Tests[[:space:]]+([0-9]+ failed, )?[1-9][0-9]* passed' "$log_file" || true)
                [ -n "$evidence" ] && verdict="ran"
            fi
            ;;
        jest)
            evidence=$(grep -m1 -E 'Test Suites:[[:space:]]+0 total' "$log_file" || true)
            if [ -n "$evidence" ]; then verdict="zero"; fi
            if [ -z "$verdict" ]; then
                evidence=$(grep -m1 -E 'Tests:[[:space:]]+0 total' "$log_file" || true)
                [ -n "$evidence" ] && verdict="zero"
            fi
            if [ -z "$verdict" ]; then
                evidence=$(grep -m1 -E 'Test Suites:[[:space:]]+([0-9]+ failed, )?[1-9][0-9]* passed' "$log_file" || true)
                [ -n "$evidence" ] && verdict="ran"
            fi
            if [ -z "$verdict" ]; then
                evidence=$(grep -m1 -E 'Tests:[[:space:]]+([0-9]+ failed, )?[1-9][0-9]* passed' "$log_file" || true)
                [ -n "$evidence" ] && verdict="ran"
            fi
            ;;
        mocha)
            evidence=$(grep -m1 -E '(^|[^0-9])0 passing' "$log_file" || true)
            if [ -n "$evidence" ]; then
                verdict="zero"
            else
                evidence=$(grep -m1 -E '(^|[^0-9])[1-9][0-9]* passing' "$log_file" || true)
                [ -n "$evidence" ] && verdict="ran"
            fi
            ;;
        tap)
            evidence=$(grep -m1 -E '^#[[:space:]]+tests[[:space:]]+0$|(^|[^0-9])0 tests' "$log_file" || true)
            if [ -n "$evidence" ]; then
                verdict="zero"
            else
                evidence=$(grep -m1 -E '^#[[:space:]]+tests[[:space:]]+[1-9][0-9]*$' "$log_file" || true)
                [ -n "$evidence" ] && verdict="ran"
            fi
            ;;
        *)
            # Unknown runner label: fall through to the generic strict check.
            ;;
    esac

    if [ "$verdict" = "zero" ]; then
        print_header 2 "ERROR: $runner suite reported ZERO tests — no coverage collected" "suite=$suite exit_code=$exit_code"
        print_header 4 "ERROR: install-and-run.sh refused to record coverage from an empty run"
        echo "  Runner summary that triggered this guard:"
        echo "    $evidence"
        echo "  Log: $log_file"
        echo "  A zero-test run produces an all-zero lcov.info that would otherwise pass"
        echo "  every structural check. Fix the runner invocation for this commit before"
        echo "  re-running."
        exit 1
    fi

    if [ -z "$verdict" ] && [ "${SUITE_RAN_STRICT:-1}" != "0" ] && [ "$exit_code" != "0" ]; then
        print_header 2 "ERROR: could not parse a test count for a non-zero $runner exit" "suite=$suite exit_code=$exit_code"
        print_header 4 "ERROR: add a summary pattern for this runner to assert-suite-ran.sh"
        echo "  Log: $log_file"
        echo "  (set SUITE_RAN_STRICT=0 to downgrade this to a warning)"
        exit 1
    fi

    if [ "$verdict" = "ran" ]; then
        echo "  [---] assert_suite_ran: $suite ran tests ($evidence)"
    fi
    return 0
}

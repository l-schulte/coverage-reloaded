#!/usr/bin/env bash
#
# na-if-focus-marker.sh — Mark a commit not-applicable when a collected test
# suite contains a focus marker (.only).
#
# SYNOPSIS
#   source /coverage_reloaded/logging.sh
#   source /coverage_reloaded/na-if-focus-marker.sh
#   na_if_focus_marker <pathspec> [<pathspec> ...]
#
# DESCRIPTION
#   A committed focus marker (`describe.only` / `it.only` / `context.only` /
#   `test.only` / `suite.only`) makes mocha or vitest execute only the marked
#   subset. The run still exits 0 and emits a structurally valid lcov, but it
#   measures the focused subset rather than the behavioral suite, so it is
#   unusable as the study's exposure variable.
#
#   We cannot know whether the rest of the suite was healthy or broken, so we
#   neither strip the marker nor record the biased coverage: at such a commit
#   full-suite coverage is not applicable, exactly as if no applicable suite
#   were specified. The commit is marked with the shared `not_applicable`
#   sentinel (see logging.sh) and the script exits 0.
#
#   Only tracked files are scanned (via `git grep`). The working tree is
#   searched, so the content mocha/vitest will load is what is inspected.
#
#   CWD must be the checked-out repository, and logging.sh must already be
#   sourced (the helper uses `print_header` and `not_applicable`).
#
# USAGE
#   Pass the roots of the *collected* suites only. An excluded suite (for
#   example Cypress specs under test/e2e, which are not collected) must not
#   trigger this guard.
#
#   # flowfuse: test:unit:forge, test:unit:frontend, test:system
#   na_if_focus_marker test/unit test/system
#
#   # apostrophe: root mocha chain, or packages/apostrophe in the monorepo era
#   na_if_focus_marker test
#   na_if_focus_marker packages/apostrophe/test
#
# EXIT STATUS
#   0   no focus marker found (the caller continues)
#   0   focus marker found; `not_applicable` writes the marker and exits 0
#   1   called without a pathspec (programming error)
#   >1  the scan itself failed (git error); propagated so the run fails loudly
#
na_if_focus_marker() {
    if [ "$#" -eq 0 ]; then
        print_header 2 "ERROR: na_if_focus_marker requires at least one pathspec"
        exit 1
    fi

    local matches rc
    set +e
    matches=$(git grep -nE '(describe|it|context|test|suite)\.only[[:space:]]*\(' -- "$@")
    rc=$?
    set -e

    case "$rc" in
        0)
            print_header 2 "Focus marker (.only) in collected suite"
            echo "$matches"
            not_applicable "Collected test suite contains a focus marker (.only); the committed suite would run only a subset, so full-suite coverage is not applicable"
            ;;
        1)
            # No match: nothing to guard against.
            ;;
        *)
            print_header 2 "ERROR: focus-marker scan failed (git grep rc=$rc)"
            exit "$rc"
            ;;
    esac
}

#!/usr/bin/env bash
#
# na-if-focus-marker.sh — Handle a committed focus marker (.only) in a collected
# test suite, according to what the runner actually does with it.
#
# SYNOPSIS
#   source /coverage_reloaded/logging.sh
#   source /coverage_reloaded/na-if-focus-marker.sh
#   na_if_focus_marker [--runner <name>]... [--exclude <pattern>] <pathspec> [<pathspec> ...]
#
# DESCRIPTION
#   A committed focus marker (`describe.only` / `it.only` / `context.only` /
#   `test.only` / `suite.only`) always means a partial run, but how much it
#   hides depends on the runner:
#
#     runner     effect of a committed .only                      policy
#     --------   ----------------------------------------------   ------------
#     mocha      run-global. Every spec file shares one process    not
#                and one global context, so `.only` truncates       applicable
#                the whole run; the lcov is indistinguishable
#                from a full-suite run.
#     jest       per-file. Each test file runs in its own          record,
#                environment, so only the marked file is           continue
#                reduced and every other file runs in full.
#     vitest     per-file; additionally `allowOnly` (default       record,
#                false) makes vitest refuse to run, and such a      continue
#                refusal surfaces as an ordinary failing run.
#     node:test  per-file; `.only` is also inert unless the        record,
#                runner is started with `--test-only`.             continue
#
#   "Not applicable" means the commit offers no full-suite measurement, so it
#   is recorded with the shared not_applicable sentinel (logging.sh) and the
#   script exits 0 — exactly as if no applicable suite were specified.
#
#   For a per-file runner the committed suite still runs in full apart from the
#   marked file(s). Refusing to measure would discard the whole commit to avoid
#   a bounded, known deficit — for some projects the marker survives for years
#   and would remove a large, non-random block of history. The run therefore
#   continues and the deficit is recorded in a `focus_marker.txt` sidecar in the
#   coverage staging area, which execute.sh copies into the commit's own output
#   directory next to its lcov files. The harness ignores the file (stats.py and
#   check_validity.py act on `*.lcov` inside commit directories and on the
#   `.error` / `.not_applicable` suffixes at the output root). It exists so
#   affected commits stay discoverable and can be censored or weighted in the
#   analysis.
#
#   Only tracked files are scanned (via `git grep`). The working tree is
#   searched, so the content the runner will load is what is inspected.
#
#   CWD must be the checked-out repository, and logging.sh must already be
#   sourced (the helper uses `print_header` and `not_applicable`).
#
# RUNNERS
#   Pass `--runner` once per runner that executes the collected suites; a
#   project with several runners passes several flags. The commit is treated as
#   not applicable when any declared runner is run-global, because a matching
#   file cannot be attributed to a specific runner without a runner-to-path map.
#
#   With no `--runner` the conservative default is assumed run-global, which
#   preserves the behaviour of callers that do not declare their runner; the
#   header states the assumption.
#
# USAGE
#   Pass the roots of the *collected* suites only. An excluded suite (for
#   example Cypress specs under test/e2e, which are not collected) must not
#   trigger this guard.
#
#   # desktop: jest until 2025-04, node:test after; both per-file
#   na_if_focus_marker --runner jest --runner node app/test/unit script eslint-rules
#
#   # apostrophe: root mocha chain, or packages/apostrophe in the monorepo era
#   na_if_focus_marker --runner mocha test
#
#   # with excluded file or directory:
#   na_if_focus_marker --runner jest --exclude path/to/excluded/spec.ts path/to/suite
#
# EXIT STATUS
#   0   no focus marker found (the caller continues)
#   0   marker found with a per-file runner; the deficit is recorded and the
#       caller continues
#   0   marker found with a run-global runner; `not_applicable` writes the
#       sentinel and exits 0
#   1   called without a pathspec (programming error)
#   2   called with an unlisted --runner name (programming error)
#   >2  the scan itself failed (git error); propagated so the run fails loudly
#
# _na_focus_marker_runner_policy <runner> — print "global" or "scoped".
# Exits 2 for a name that is not in the table above, so a typo cannot silently
# downgrade a run-global runner (or the reverse) for a whole project.
_na_focus_marker_runner_policy() {
    case "${1,,}" in
        mocha) echo "global" ;;
        jest | vitest | node | node:test | nodetest) echo "scoped" ;;
        *)
            print_header 2 "ERROR: unknown --runner '$1'" \
                "known: mocha (run-global); jest, vitest, node (per-file)"
            exit 2
            ;;
    esac
}

# _na_focus_marker_record <runner-label> <marker-count> <file-count> <matches>
# Write the deficit sidecar into the coverage staging area, from where
# execute.sh copies it in next to the commit's lcov files — the same two-stage
# route the suite lcov and exit-code files take via find-and-move-lcov.sh. The
# sidecar therefore ends up inside <output>/<timestamp>_<revision>/ with the
# coverage it qualifies, rather than at the output root.
_na_focus_marker_record() {
    local runner_label="$1"
    local marker_count="$2"
    local file_count="$3"
    local matches="$4"
    local marker="${COVERAGE_REPORT_PATH:-/coverage_reloaded/exported}/focus_marker.txt"

    mkdir -p "$(dirname "$marker")"
    {
        echo "Commit: ${revision}"
        echo "Timestamp: ${timestamp}"
        echo "Project: ${project_id:-}"
        echo "Runner: ${runner_label}"
        echo "Policy: per-file .only — the run continues, the marked file(s) only are reduced"
        echo "Markers: ${marker_count}"
        echo "Affected files: ${file_count}"
        echo "Matches:"
        printf '%s\n' "$matches" | sed 's/^/  /'
        echo "Note: coverage for this commit is valid for every file not listed above. Within the files listed above, the tests that are not marked .only did not execute."
    } > "$marker"

    print_header 4 "NOTICE: recorded the focus-marker deficit in $(basename "$marker")" \
        "execute.sh copies it into ${timestamp}_${revision}/"
}

na_if_focus_marker() {
    if [ "$#" -eq 0 ]; then
        print_header 2 "ERROR: na_if_focus_marker requires at least one pathspec"
        exit 1
    fi

    local includes=()
    local excludes=()
    local runners=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --runner|-r)
                shift
                if [ "$#" -eq 0 ]; then
                    print_header 2 "ERROR: --runner requires a runner name argument"
                    exit 1
                fi
                runners+=("$1")
                ;;
            --runner=*)
                runners+=("${1#*=}")
                ;;
            --exclude|-x)
                shift
                if [ "$#" -eq 0 ]; then
                    print_header 2 "ERROR: --exclude requires a pattern argument"
                    exit 1
                fi
                excludes+=(":(exclude)$1")
                ;;
            --exclude=*)
                excludes+=(":(exclude)${1#*=}")
                ;;
            --)
                shift
                includes+=("$@")
                break
                ;;
            *)
                includes+=("$1")
                ;;
        esac
        shift
    done

    if [ "${#includes[@]}" -eq 0 ]; then
        print_header 2 "ERROR: na_if_focus_marker requires at least one inclusion pathspec"
        exit 1
    fi

    # Effective policy: not applicable only when some declared runner truncates
    # the whole run on .only. Without a declaration, assume run-global.
    local effective="global"
    local runner_label="unspecified — assumed run-global"
    if [ "${#runners[@]}" -gt 0 ]; then
        runner_label="${runners[*]}"
        effective="scoped"
        local runner policy
        for runner in "${runners[@]}"; do
            policy="$(_na_focus_marker_runner_policy "$runner")"
            if [ "$policy" = "global" ]; then
                effective="global"
            fi
        done
    fi

    local matches rc
    set +e
    matches=$(git grep -nE '(describe|it|context|test|suite)\.only[[:space:]]*\(' -- "${includes[@]}" "${excludes[@]}")
    rc=$?
    set -e

    case "$rc" in
        0)
            local marker_count file_count
            marker_count=$(printf '%s\n' "$matches" | grep -c .)
            file_count=$(printf '%s\n' "$matches" | cut -d: -f1 | sort -u | grep -c .)

            if [ "$effective" = "global" ]; then
                print_header 2 "Focus marker (.only) in collected suite" \
                    "runner: $runner_label — .only truncates the whole run"
                echo "$matches"
                # Reason text is intentionally unchanged from the pre-runner-aware
                # helper so that markers already on disk stay comparable; the
                # runner is reported in the header above.
                not_applicable "Collected test suite contains a focus marker (.only); the committed suite would run only a subset, so full-suite coverage is not applicable"
            fi

            print_header 2 "Focus marker (.only) in collected suite — bounded deficit" \
                "runner: $runner_label — .only is scoped per file"
            echo "$matches"
            _na_focus_marker_record "$runner_label" "$marker_count" "$file_count" "$matches"
            print_header 4 "NOTICE: continuing — only the file(s) listed above are reduced" \
                "$marker_count marker(s) in $file_count file(s)"
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

#!/usr/bin/env bash
#
# has-option.sh — Check if a CLI executable supports a given option flag.
#
# SYNOPSIS
#   source has-option.sh
#   has_option <executable> <option> [--help-arg=<arg>]
#
# DESCRIPTION
#   Runs `<executable> --help` (or a custom help arg) and checks whether
#   the given option appears in the output.  Returns 0 (true) if found,
#   1 (false) if not, and 2 if the help command itself fails.
#
#   This is useful for conditionally passing flags that only exist in
#   certain versions of a tool — e.g. `--bail` in vitest, `--changed`
#   in jest, etc.
#
#   Matching is done via a word-boundary grep on the option name so
#   that `--bail` does not falsely match `--bail=0` or `--no-bail`.
#   Use `--exact` for strict line-level matching instead.
#
# USAGE
#   source /coverage_reloaded/has-option.sh
#
#   if has_option vitest --bail; then
#       VITEST_BAIL="--bail=0"
#   else
#       VITEST_BAIL=""
#   fi
#
#   npx vitest run ${VITEST_BAIL:+"$VITEST_BAIL"}
#
# OPTIONS
#   --help-arg=<arg>  Use a custom argument to retrieve help text
#                     (default: --help).  Useful for tools that use
#                     -h or --help-full.
#   --exact           Match the option as a complete line (anchored),
#                     rather than as a word-boundary pattern.
#
# ENVIRONMENT
#   HAS_OPTION_QUIET  Set to "1" to suppress stderr from the help
#                     command (default: 0).

has_option() {
    local executable="$1"
    local option="$2"
    local help_arg="--help"
    local exact=0

    # Parse optional flags
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help-arg=*) help_arg="${1#*=}" ;;
            --exact)      exact=1 ;;
            *)            echo "has_option: unknown argument '$1'" >&2; return 2 ;;
        esac
        shift
    done

    # Validate inputs
    if [[ -z "$executable" ]] || [[ -z "$option" ]]; then
        echo "has_option: usage: has_option <executable> <option> [--help-arg=<arg>] [--exact]" >&2
        return 2
    fi

    # Resolve the executable path
    local exe_path
    exe_path="$(command -v "$executable" 2>/dev/null)" || {
        [[ "${HAS_OPTION_QUIET:-0}" -eq 0 ]] && echo "has_option: '$executable' not found" >&2
        return 2
    }

    # Get help text
    local help_text
    help_text="$("$exe_path" "$help_arg" 2>/dev/null)" || {
        [[ "${HAS_OPTION_QUIET:-0}" -eq 0 ]] && echo "has_option: '$executable $help_arg' exited with code $?" >&2
        return 2
    }

    if [[ -z "$help_text" ]]; then
        [[ "${HAS_OPTION_QUIET:-0}" -eq 0 ]] && echo "has_option: '$executable $help_arg' produced no output" >&2
        return 2
    fi

    # Match
    if [[ "$exact" -eq 1 ]]; then
        # Line-level match: the option appears as a whole line (possibly indented)
        echo "$help_text" | grep -q "^[[:space:]]*${option}[[:space:]]"
    else
        # Word-boundary match: the option appears as a distinct word
        # Escape special regex chars in the option name
        local escaped_option
        escaped_option="$(sed 's/[^^]/[&]/g; s/\^/\\^/g' <<<"$option")"
        echo "$help_text" | grep -qi "${escaped_option}"
    fi

    return $?
}

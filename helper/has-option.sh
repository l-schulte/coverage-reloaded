#!/usr/bin/env bash
#
# has-option.sh — Check if a CLI command supports a given option flag.
#
# SYNOPSIS
#   source has-option.sh
#   has_option <option> <command...>
#
# DESCRIPTION
#   Runs `<command...> --help` (or a custom help arg) and checks whether
#   the given option appears in the output.  Returns 0 (true) if found,
#   1 (false) if not, and 2 if the help command itself fails.
#
#   The command is whatever you would type at the shell — a simple binary,
#   a path, or a compound command like `npx --registry=... vitest`.
#   This makes it easy to check tools that are resolved by npx, or that
#   need specific flags to run correctly.
#
#   Matching is done via a word-boundary grep on the option name so
#   that `--bail` does not falsely match `--bail=0` or `--no-bail`.
#   Use `--exact` for strict line-level matching instead.
#
# USAGE
#   source /coverage_reloaded/has-option.sh
#
#   # Simple binary
#   if has_option --bail vitest; then ...
#
#   # Compound command (npx, docker, etc.)
#   if has_option --bail npx --registry=$WAYPACK_NPM_REGISTRY vitest; then ...
#
#   # Full path
#   if has_option --bail ./node_modules/.bin/vitest; then ...
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
    local option=""
    local help_arg="--help"
    local exact=0

    # Parse leading flags (--help-arg=, --exact) and extract <option>
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help-arg=*) help_arg="${1#*=}"; shift ;;
            --exact)      exact=1; shift ;;
            --*)          option="$1"; shift; break ;;
            *)            echo "has_option: expected an option (--xxx) as first argument, got '$1'" >&2; return 2 ;;
        esac
    done

    # Remaining args are the command
    local -a cmd=("$@")

    # Validate
    if [[ -z "$option" ]] || [[ ${#cmd[@]} -eq 0 ]]; then
        echo "has_option: usage: has_option [--help-arg=<arg>] [--exact] <option> <command...>" >&2
        return 2
    fi

    # Get help text by running: <command...> <help_arg>
    local help_text
    help_text="$("${cmd[@]}" "$help_arg" 2>/dev/null)" || {
        [[ "${HAS_OPTION_QUIET:-0}" -eq 0 ]] && echo "has_option: '${cmd[*]} $help_arg' exited with code $?" >&2
        return 2
    }

    if [[ -z "$help_text" ]]; then
        [[ "${HAS_OPTION_QUIET:-0}" -eq 0 ]] && echo "has_option: '${cmd[*]} $help_arg' produced no output" >&2
        return 2
    fi

    # Match
    if [[ "$exact" -eq 1 ]]; then
        echo "$help_text" | grep -q "^[[:space:]]*${option}[[:space:]]"
    else
        local escaped_option
        escaped_option="$(sed 's/[^^]/[&]/g; s/\^/\\^/g' <<<"$option")"
        echo "$help_text" | grep -qi "${escaped_option}"
    fi

    return $?
}


has_script() {
    node -e "const p=require('./package.json'); process.exit((p.scripts && p.scripts['$1']) ? 0 : 1)"
}

#!/usr/bin/env bash

# ── Formatting ────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

# strip formatting when writing to a file / pipe
if [[ ! -t 1 ]]; then
    BOLD='' DIM='' RED='' YELLOW='' GREEN='' CYAN='' RESET=''
fi

# print_header <level> <title> [subtitle]
#   level 1 → double-line box   (major phase)
#   level 2 → single-line box   (sub-phase)
#   level 3 → dashed box        (step)
#   level 4 → bracketed inline  (detail / status)
print_header() {
    local level="$1"
    local title="$2"
    local subtitle="${3:-}"
    local width=60

    case "$level" in
        1)
            local bar
            bar=$(printf '═%.0s' $(seq 1 $width))
            echo -e "\n${CYAN}${BOLD}╔${bar}╗${RESET}"
            printf "${CYAN}${BOLD}║  %-*s  ║${RESET}\n" "$((width - 4))" "$title"
            if [[ -n "$subtitle" ]]; then
                printf "${CYAN}${DIM}║  %-*s  ║${RESET}\n" "$((width - 4))" "$subtitle"
            fi
            echo -e "${CYAN}${BOLD}╚${bar}╝${RESET}\n"
            ;;
        2)
            local bar
            bar=$(printf '─%.0s' $(seq 1 $width))
            echo -e "\n${BOLD}┌${bar}┐${RESET}"
            printf "${BOLD}│  %-*s  │${RESET}\n" "$((width - 4))" "$title"
            if [[ -n "$subtitle" ]]; then
                printf "${DIM}│  %-*s  │${RESET}\n" "$((width - 4))" "$subtitle"
            fi
            echo -e "${BOLD}└${bar}┘${RESET}\n"
            ;;
        3)
            local bar
            bar=$(printf '╌%.0s' $(seq 1 $width))
            echo -e "\n${DIM}╌${bar}╌${RESET}"
            printf "  ${BOLD}%-*s${RESET}\n" "$((width - 4))" "$title"
            if [[ -n "$subtitle" ]]; then
                printf "  ${DIM}%-*s${RESET}\n" "$((width - 4))" "$subtitle"
            fi
            echo -e "${DIM}╌${bar}╌${RESET}\n"
            ;;
        4)
            local prefix color
            case "$title" in
                WARNING:*) prefix="WRN" color="$YELLOW" ;;
                NOTICE:*)  prefix="NFO" color="$CYAN"   ;;
                ERROR:*)   prefix="ERR" color="$RED"    ;;
                *)         prefix="---" color="$DIM"    ;;
            esac
            echo -e "  ${color}${BOLD}[${prefix}]${RESET} ${title}${subtitle:+  ${DIM}— $subtitle${RESET}}"
            ;;
        *)
            echo -e "${RED}print_header: unknown level '$level'${RESET}" >&2
            return 1
            ;;
    esac
}

# ── Suite start/end markers (level-2 boxed) ───────────────────
#
# These emit a single-line box (same visual level as print_header level 2)
# with machine-parseable markers inside. The box makes suite boundaries
# clearly visible in logs while the [SUITE_START]/[SUITE_END] tokens
# remain extractable by automated tools.
#
# Format:
#   [SUITE_START] <suite_name>
#   [SUITE_END]   <suite_name>
#
# The <suite_name> is a short kebab-case identifier (e.g. "unit", "integration",
# "client-unit", "server-unit"). The description is optional human-readable text.
#
# Usage:
#   suite_start "unit" "Running unit tests with jest --coverage"
#   suite_end "unit" "$EXIT_CODE"

suite_start() {
    local name="$1"
    local description="${2:-}"
    local width=60
    local bar
    bar=$(printf '─%.0s' $(seq 1 $width))
    echo ""
    echo -e "${BOLD}╭${bar}╮${RESET}"
    printf "${BOLD}│  [SUITE_START] %-*s  │${RESET}\n" "$((width - 18))" "$name"
    if [[ -n "$description" ]]; then
        printf "${DIM}│  %-*s  │${RESET}\n" "$((width - 5))" "$description"
    fi
    echo -e "${BOLD}╰${bar}╯${RESET}"
    echo ""
}

suite_end() {
    local name="$1"
    local exit_code="${2:-}"
    local width=60
    local bar
    bar=$(printf '─%.0s' $(seq 1 $width))
    echo ""
    echo -e "${BOLD}╭${bar}╮${RESET}"
    printf "${BOLD}│  [SUITE_END]   %-*s  │${RESET}\n" "$((width - 18))" "$name"
    if [[ -n "$exit_code" ]]; then
        local color="$GREEN"
        [[ "$exit_code" != "0" ]] && color="$RED"
        printf "${color}│  %-*s  │${RESET}\n" "$((width - 5))" "exit_code=${exit_code}"
    fi
    echo -e "${BOLD}╰${bar}╯${RESET}"
    echo ""
}

# ── Not-applicable sentinel ───────────────────────────────────
#
# Signals that a commit has no test infrastructure to run. The marker file is
# the single source of truth: execute.sh and docker_run.py detect it directly
# instead of interpreting an exit code, so an ordinary command failing with a
# given code (npm uses 2 for install errors) can never be mistaken for this.
# The script still exits 0 so that run-level exit codes only distinguish
# success (0) from failure (non-zero).
#
# Usage:
#   not_applicable "No package.json at this commit"
not_applicable() {
    local reason="${1:-no test infrastructure at this commit}"
    local marker="${OUTPUT_PATH:-/coverage_reloaded/coverage}/${timestamp}_${revision}.not_applicable"
    {
        echo "Commit: ${revision}"
        echo "Timestamp: ${timestamp}"
        echo "Project: ${project_id:-}"
        echo "Reason: ${reason}"
    } > "$marker"
    print_header 2 "NOT APPLICABLE" "$reason"
    exit 0
}
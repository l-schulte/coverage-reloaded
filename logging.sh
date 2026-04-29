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
#   level 1 → full-width banner  (major phase)
#   level 2 → section divider    (sub-phase)
#   level 3 → inline label       (step)
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
            echo -e "${BOLD}└${bar}┘${RESET}"
            ;;
        3)
            echo -e "\n${BOLD}▶ ${title}${RESET}${DIM}${subtitle:+  — $subtitle}${RESET}"
            ;;
        *)
            echo -e "${RED}print_header: unknown level '$level'${RESET}" >&2
            return 1
            ;;
    esac
}
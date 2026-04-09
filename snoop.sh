#!/usr/bin/env bash
#
# snoop — Dev Environment Privacy & IP Leakage Audit CLI
#
# Usage:
#   ./snoop.sh                         # Report mode (default)
#   ./snoop.sh --interactive           # Interactive remediation
#   ./snoop.sh --only editor,secrets   # Scan specific categories
#   ./snoop.sh --skip network,deps     # Skip specific categories
#   ./snoop.sh --format json           # JSON output
#   ./snoop.sh --scan-path ~/projects  # Custom scan path
#
# No dependencies. Pure bash. No telemetry.

set -uo pipefail

SNOOP_VERSION="0.1.0"
SNOOP_SOURCE="${BASH_SOURCE[0]}"
# Resolve symlinks to find the real script location
while [[ -L "$SNOOP_SOURCE" ]]; do
    SNOOP_DIR="$(cd "$(dirname "$SNOOP_SOURCE")" && pwd)"
    SNOOP_SOURCE="$(readlink "$SNOOP_SOURCE")"
    [[ "$SNOOP_SOURCE" != /* ]] && SNOOP_SOURCE="${SNOOP_DIR}/${SNOOP_SOURCE}"
done
SNOOP_DIR="$(cd "$(dirname "$SNOOP_SOURCE")" && pwd)"

# Source libraries
source "${SNOOP_DIR}/lib/utils.sh"
source "${SNOOP_DIR}/lib/output.sh"
source "${SNOOP_DIR}/lib/interactive.sh"

# Source check modules
source "${SNOOP_DIR}/lib/checks/editor.sh"
source "${SNOOP_DIR}/lib/checks/git.sh"
source "${SNOOP_DIR}/lib/checks/secrets.sh"
source "${SNOOP_DIR}/lib/checks/system.sh"
source "${SNOOP_DIR}/lib/checks/apps.sh"
source "${SNOOP_DIR}/lib/checks/network.sh"
source "${SNOOP_DIR}/lib/checks/deps.sh"

# Source remediation modules
source "${SNOOP_DIR}/lib/remediate/editor.sh"
source "${SNOOP_DIR}/lib/remediate/git.sh"
source "${SNOOP_DIR}/lib/remediate/secrets.sh"
source "${SNOOP_DIR}/lib/remediate/system.sh"
source "${SNOOP_DIR}/lib/remediate/apps.sh"

# ─── Globals ───────────────────────────────────────────────────────────────────

INTERACTIVE=false
FORMAT="text"
SCAN_PATH="${HOME}"
ALL_CATEGORIES="editor git secrets system apps network deps"

# ─── Argument Parsing ──────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
snoop — Dev Environment Privacy & IP Leakage Audit CLI

Usage:
  snoop [options]

Options:
  --interactive          Walk through each finding and optionally apply fixes
  --only <categories>    Only run specific categories (comma-separated)
  --skip <categories>    Skip specific categories (comma-separated)
  --format <text|json>   Output format (default: text)
  --scan-path <path>     Custom path to scan for secrets/repos (default: ~/)
  --version              Show version
  --help                 Show this help

Categories:
  editor    Editor & IDE telemetry (VS Code, Cursor, JetBrains)
  git       Git & version control configuration
  secrets   Secrets & credentials exposure
  system    System & disk security (encryption, firewall)
  apps      Application telemetry (Homebrew, npm, Docker)
  network   DNS & network configuration
  deps      Dependency manager settings

Examples:
  snoop                              # Full audit, report mode
  snoop --interactive                # Audit + guided remediation
  snoop --only editor,secrets        # Scan only editor and secrets
  snoop --format json                # Machine-readable output
  snoop --scan-path ~/projects       # Scan a specific directory
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interactive)
                INTERACTIVE=true
                shift
                ;;
            --only)
                ONLY_CATEGORIES="$2"
                shift 2
                ;;
            --skip)
                SKIP_CATEGORIES="$2"
                shift 2
                ;;
            --format)
                FORMAT="$2"
                shift 2
                ;;
            --scan-path)
                SCAN_PATH="$2"
                shift 2
                ;;
            --version)
                echo "snoop v${SNOOP_VERSION}"
                exit 0
                ;;
            --help|-h)
                usage
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Run 'snoop --help' for usage." >&2
                exit 2
                ;;
        esac
    done

    # Validate format
    if [[ "$FORMAT" != "text" && "$FORMAT" != "json" ]]; then
        echo "Invalid format: $FORMAT. Use 'text' or 'json'." >&2
        exit 2
    fi
}

# ─── Main ──────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"

    detect_os

    # Run checks for each enabled category
    for category in $ALL_CATEGORIES; do
        if should_run_category "$category"; then
            case "$category" in
                editor)  run_editor_checks ;;
                git)     run_git_checks ;;
                secrets) run_secrets_checks ;;
                system)  run_system_checks ;;
                apps)    run_apps_checks ;;
                network) run_network_checks ;;
                deps)    run_deps_checks ;;
            esac
        fi
    done

    # Output results
    if [[ "$FORMAT" == "json" ]]; then
        output_json
    else
        output_report
    fi

    # Interactive mode
    if [[ "$INTERACTIVE" == true ]]; then
        run_interactive
    fi

    # Exit code: 1 if any CRITICAL or HIGH findings
    local has_critical_or_high=false
    for finding in "${FINDINGS[@]}"; do
        local sev="${finding%%|*}"
        if [[ "$sev" == "CRITICAL" || "$sev" == "HIGH" ]]; then
            has_critical_or_high=true
            break
        fi
    done

    if [[ "$has_critical_or_high" == true ]]; then
        exit 1
    fi
    exit 0
}

main "$@"

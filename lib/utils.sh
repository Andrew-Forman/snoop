#!/usr/bin/env bash
# snoop — Utility functions

OS_TYPE=""

# ─── Globals ───────────────────────────────────────────────────────────────────

declare -a FINDINGS=()
ONLY_CATEGORIES=""
SKIP_CATEGORIES=""

# ─── Finding Registration ─────────────────────────────────────────────────────

# Called by check functions to register a finding
# Usage: add_finding SEVERITY CATEGORY "Title" "File" "Current Value" "Risk" "Fix Description" "Trade-off" "fix_function_name"
add_finding() {
    local severity="$1"
    local category="$2"
    local title="$3"
    local file="${4:-}"
    local current="${5:-}"
    local risk="${6:-}"
    local fix_desc="${7:-}"
    local tradeoff="${8:-}"
    local fix_func="${9:-}"

    FINDINGS+=("${severity}|${category}|${title}|${file}|${current}|${risk}|${fix_desc}|${tradeoff}|${fix_func}")
}

# ─── Category Selection ────────────────────────────────────────────────────────

should_run_category() {
    local category="$1"

    if [[ -n "$ONLY_CATEGORIES" ]]; then
        echo "$ONLY_CATEGORIES" | tr ',' '\n' | grep -qx "$category"
        return $?
    fi

    if [[ -n "$SKIP_CATEGORIES" ]]; then
        if echo "$SKIP_CATEGORIES" | tr ',' '\n' | grep -qx "$category"; then
            return 1
        fi
    fi

    return 0
}

# ─── OS Detection ─────────────────────────────────────────────────────────────

detect_os() {
    case "$(uname -s)" in
        Darwin*) OS_TYPE="macos" ;;
        Linux*)  OS_TYPE="linux" ;;
        *)       OS_TYPE="unknown" ;;
    esac
}

is_macos() { [[ "$OS_TYPE" == "macos" ]]; }
is_linux() { [[ "$OS_TYPE" == "linux" ]]; }

# Backup a file before modifying it
# Creates <file>.snoop.bak.<timestamp>
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local timestamp
        timestamp="$(date +%Y%m%d_%H%M%S)"
        cp "$file" "${file}.snoop.bak.${timestamp}"
        echo "  Backed up: ${file} → ${file}.snoop.bak.${timestamp}"
    fi
}

# Check if a command exists
has_command() {
    command -v "$1" &>/dev/null
}

# Read a JSON value using jq if available, otherwise basic grep/sed
# Usage: json_get_value <file> <key>
# Returns the value or empty string
json_get_value() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return
    fi

    if has_command jq; then
        jq -r ".\"${key}\" // empty" "$file" 2>/dev/null || echo ""
    else
        # Basic fallback: grep for "key": "value" or "key": value
        grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null \
            | head -1 \
            | sed 's/.*:[[:space:]]*"\(.*\)"/\1/' \
            || echo ""
    fi
}

# Read a nested JSON value (dot-separated path)
# Usage: json_get_nested <file> <path.to.key>
json_get_nested() {
    local file="$1"
    local key_path="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return
    fi

    # Try jq first, fall back to grep (VS Code settings are JSONC, which jq can't parse)
    if has_command jq; then
        local jq_result
        jq_result="$(jq -r --arg key "$key_path" 'if has($key) then .[$key] | tostring else empty end' "$file" 2>/dev/null)" && [[ -n "$jq_result" ]] && echo "$jq_result" && return
    fi

    # Fallback: grep for "key": "value" or "key": true/false/number
    local match
    match="$(grep -o "\"${key_path}\"[[:space:]]*:[[:space:]]*[^,}]*" "$file" 2>/dev/null | head -1)" || true
    if [[ -n "$match" ]]; then
        # Extract value — strip key, colon, whitespace, and surrounding quotes
        echo "$match" | sed 's/.*:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed 's/[[:space:]]*$//'
    else
        echo ""
    fi
}

# Set a JSON value in a file (requires jq)
# Falls back to sed-based approach if jq unavailable
json_set_value() {
    local file="$1"
    local key="$2"
    local value="$3"

    if has_command jq; then
        local tmp
        tmp="$(mktemp)"
        jq ".\"${key}\" = ${value}" "$file" > "$tmp" && mv "$tmp" "$file"
    else
        # Basic sed fallback — only works for simple top-level keys
        if grep -q "\"${key}\"" "$file" 2>/dev/null; then
            sed -i.tmp "s/\"${key}\"[[:space:]]*:[[:space:]]*[^,}]*/\"${key}\": ${value}/" "$file"
            rm -f "${file}.tmp"
        else
            # Insert before the closing brace
            sed -i.tmp "s/^}$/  \"${key}\": ${value}\n}/" "$file"
            rm -f "${file}.tmp"
        fi
    fi
}

# Get VS Code settings.json path based on OS and variant
# Usage: get_vscode_settings_path [code|codium|cursor]
get_vscode_settings_path() {
    local variant="${1:-code}"

    local dir_name
    case "$variant" in
        code)    dir_name="Code" ;;
        codium)  dir_name="VSCodium" ;;
        cursor)  dir_name="Cursor" ;;
        *)       dir_name="Code" ;;
    esac

    if is_macos; then
        echo "${HOME}/Library/Application Support/${dir_name}/User/settings.json"
    elif is_linux; then
        echo "${HOME}/.config/${dir_name}/User/settings.json"
    fi
}

# Severity ordering for sorting
severity_rank() {
    case "$1" in
        CRITICAL) echo 0 ;;
        HIGH)     echo 1 ;;
        MEDIUM)   echo 2 ;;
        LOW)      echo 3 ;;
        INFO)     echo 4 ;;
        *)        echo 5 ;;
    esac
}

# Color codes
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

severity_color() {
    case "$1" in
        CRITICAL) echo "${RED}${BOLD}" ;;
        HIGH)     echo "${RED}" ;;
        MEDIUM)   echo "${YELLOW}" ;;
        LOW)      echo "${BLUE}" ;;
        INFO)     echo "${CYAN}" ;;
        *)        echo "${NC}" ;;
    esac
}

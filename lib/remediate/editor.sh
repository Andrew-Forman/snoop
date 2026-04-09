#!/usr/bin/env bash
# snoop — Editor remediation functions

# VS Code/Cursor settings are JSONC (JSON with Comments, trailing commas),
# which jq cannot parse. All remediation functions try jq first and fall
# back to sed for JSONC files.

_jsonc_set_string() {
    local file="$1" key="$2" value="$3"

    # Try jq first
    if has_command jq; then
        local tmp
        tmp="$(mktemp)"
        if jq ".\"${key}\" = \"${value}\"" "$file" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$file"
            return 0
        fi
        rm -f "$tmp"
    fi

    # Fallback: sed for JSONC
    if grep -q "\"${key}\"" "$file" 2>/dev/null; then
        sed -i.tmp "s/\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"${key}\": \"${value}\"/" "$file"
        rm -f "${file}.tmp"
    else
        # Key doesn't exist — insert before closing brace, with comma on previous line
        # Find last non-empty, non-brace line and ensure it has a trailing comma
        sed -i.tmp '$s/^}/  "'"${key}"'": "'"${value}"'"\n}/' "$file"
        rm -f "${file}.tmp"
    fi
}

_jsonc_set_bool() {
    local file="$1" key="$2" value="$3"

    # Try jq first
    if has_command jq; then
        local tmp
        tmp="$(mktemp)"
        if jq ".\"${key}\" = ${value}" "$file" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$file"
            return 0
        fi
        rm -f "$tmp"
    fi

    # Fallback: sed for JSONC
    if grep -q "\"${key}\"" "$file" 2>/dev/null; then
        sed -i.tmp "s/\"${key}\"[[:space:]]*:[[:space:]]*[^,}]*/\"${key}\": ${value}/" "$file"
        rm -f "${file}.tmp"
    else
        sed -i.tmp '$s/^}/  "'"${key}"'": '"${value}"'\n}/' "$file"
        rm -f "${file}.tmp"
    fi
}

remediate_vscode_telemetry_level() {
    local file="$1"
    [[ -z "$file" ]] && return 1

    backup_file "$file"

    if [[ -f "$file" ]]; then
        _jsonc_set_string "$file" "telemetry.telemetryLevel" "off"
    else
        mkdir -p "$(dirname "$file")"
        echo '{
  "telemetry.telemetryLevel": "off"
}' > "$file"
    fi
    echo "Set telemetry.telemetryLevel = off in ${file}"
}

remediate_vscode_experiments() {
    local file="$1"
    [[ -z "$file" ]] && return 1

    backup_file "$file"

    if [[ -f "$file" ]]; then
        _jsonc_set_bool "$file" "workbench.enableExperiments" "false"
    fi
    echo "Set workbench.enableExperiments = false in ${file}"
}

remediate_vscode_nls() {
    local file="$1"
    [[ -z "$file" ]] && return 1

    backup_file "$file"

    if [[ -f "$file" ]]; then
        _jsonc_set_bool "$file" "workbench.settings.enableNaturalLanguageSearch" "false"
    fi
    echo "Set workbench.settings.enableNaturalLanguageSearch = false in ${file}"
}

#!/usr/bin/env bash
# snoop — Application telemetry remediation functions

remediate_homebrew_analytics() {
    local _file="$1"

    if has_command brew; then
        brew analytics off 2>/dev/null
        echo "Homebrew analytics disabled."
    else
        echo "brew command not found."
        return 1
    fi
}

remediate_npm_telemetry() {
    local _file="$1"
    local npmrc="${HOME}/.npmrc"

    if [[ -f "$npmrc" ]]; then
        backup_file "$npmrc"
    fi

    # Add update-notifier=false if not present
    if [[ -f "$npmrc" ]] && grep -q 'update-notifier' "$npmrc" 2>/dev/null; then
        sed -i.tmp 's/update-notifier=.*/update-notifier=false/' "$npmrc"
        rm -f "${npmrc}.tmp"
    else
        echo "update-notifier=false" >> "$npmrc"
    fi

    echo "Set update-notifier=false in ${npmrc}"
}

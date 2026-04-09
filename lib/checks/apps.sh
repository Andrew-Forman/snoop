#!/usr/bin/env bash
# snoop — Application telemetry checks

run_apps_checks() {
    _check_homebrew_analytics
    _check_npm_telemetry
    _check_docker_telemetry
}

_check_homebrew_analytics() {
    has_command brew || return

    local analytics_disabled
    analytics_disabled="$(brew analytics state 2>/dev/null || echo "")"

    if ! echo "$analytics_disabled" | grep -qi "disabled"; then
        add_finding "LOW" "apps" \
            "Homebrew analytics are enabled" \
            "" \
            "Analytics: enabled" \
            "Homebrew sends anonymized usage data (install commands, OS version, hardware info) to Google Analytics." \
            "Run: brew analytics off" \
            "None — Homebrew works identically with analytics disabled." \
            "remediate_homebrew_analytics"
    fi
}

_check_npm_telemetry() {
    has_command npm || return

    # Check for audit/fund/update-notifier settings
    local npmrc="${HOME}/.npmrc"

    local has_audit_off=false
    local has_fund_off=false

    if [[ -f "$npmrc" ]]; then
        grep -q 'audit=false' "$npmrc" 2>/dev/null && has_audit_off=true
        grep -q 'fund=false' "$npmrc" 2>/dev/null && has_fund_off=true
    fi

    # Check for update notifier (phones home to check for updates)
    local update_notifier=true
    if [[ -f "$npmrc" ]] && grep -q 'update-notifier=false' "$npmrc" 2>/dev/null; then
        update_notifier=false
    fi

    if [[ "$update_notifier" == true ]]; then
        add_finding "LOW" "apps" \
            "npm update notifier phones home" \
            "$npmrc" \
            "update-notifier not disabled" \
            "npm checks the registry for newer versions of itself, sending your npm version and Node.js version to npmjs.org." \
            "Add 'update-notifier=false' to ~/.npmrc" \
            "You won't get prompted about npm updates. Run 'npm -v' manually to check." \
            "remediate_npm_telemetry"
    fi
}

_check_docker_telemetry() {
    local docker_settings=""

    if is_macos; then
        docker_settings="${HOME}/Library/Group Containers/group.com.docker/settings.json"
    elif is_linux; then
        docker_settings="${HOME}/.docker/desktop/settings.json"
    fi

    [[ ! -f "$docker_settings" ]] && return

    local analytics
    analytics="$(json_get_value "$docker_settings" "analyticsEnabled" 2>/dev/null || echo "")"

    if [[ "$analytics" != "false" ]]; then
        add_finding "LOW" "apps" \
            "Docker Desktop analytics are enabled" \
            "$docker_settings" \
            "analyticsEnabled = ${analytics:-not set}" \
            "Docker Desktop sends usage analytics to Docker Inc." \
            "Disable in Docker Desktop: Settings → General → Send usage statistics" \
            "None — Docker works identically." \
            ""
    fi
}

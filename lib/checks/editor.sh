#!/usr/bin/env bash
# snoop — Editor & IDE telemetry checks

run_editor_checks() {
    _check_vscode_telemetry "code"
    _check_vscode_telemetry "codium"
    _check_vscode_telemetry "cursor"
    _check_vscode_extensions
    _check_jetbrains_telemetry
}

_check_vscode_telemetry() {
    local variant="$1"
    local settings_path
    settings_path="$(get_vscode_settings_path "$variant")"

    [[ ! -f "$settings_path" ]] && return

    local label
    case "$variant" in
        code)    label="VS Code" ;;
        codium)  label="VSCodium" ;;
        cursor)  label="Cursor" ;;
    esac

    # telemetry.telemetryLevel
    local telem_level
    telem_level="$(json_get_nested "$settings_path" "telemetry.telemetryLevel")"

    if [[ -z "$telem_level" || "$telem_level" != "off" ]]; then
        add_finding "HIGH" "editor" \
            "${label} telemetry is enabled" \
            "$settings_path" \
            "telemetry.telemetryLevel = ${telem_level:-\"(not set, defaults to 'all')\"}" \
            "${label} sends usage data, error reports, and extension usage patterns to Microsoft/vendor. This can include file names, extension interactions, and command usage frequency." \
            "Set telemetry.telemetryLevel to \"off\"" \
            "You lose automatic crash reporting and may not receive targeted extension recommendations. No impact on core editor functionality." \
            "remediate_vscode_telemetry_level"
    fi

    # workbench.enableExperiments
    local experiments
    experiments="$(json_get_nested "$settings_path" "workbench.enableExperiments")"

    if [[ -z "$experiments" || "$experiments" != "false" ]]; then
        add_finding "LOW" "editor" \
            "${label} A/B experiments enabled" \
            "$settings_path" \
            "workbench.enableExperiments = ${experiments:-\"(not set, defaults to true)\"}" \
            "${label} may enroll you in experimental feature rollouts, which involves phoning home to check experiment assignments." \
            "Set workbench.enableExperiments to false" \
            "You won't get early access to experimental features. Most users never notice." \
            "remediate_vscode_experiments"
    fi

    # workbench.settings.enableNaturalLanguageSearch
    local nls
    nls="$(json_get_nested "$settings_path" "workbench.settings.enableNaturalLanguageSearch")"

    if [[ -z "$nls" || "$nls" != "false" ]]; then
        add_finding "LOW" "editor" \
            "${label} natural language settings search enabled" \
            "$settings_path" \
            "workbench.settings.enableNaturalLanguageSearch = ${nls:-\"(not set, defaults to true)\"}" \
            "Settings search queries are sent to an online service for natural language processing." \
            "Set workbench.settings.enableNaturalLanguageSearch to false" \
            "Settings search becomes keyword-only. Still fully functional." \
            "remediate_vscode_nls"
    fi

    # VSCodium suggestion
    if [[ "$variant" == "code" ]]; then
        local codium_path
        codium_path="$(get_vscode_settings_path "codium")"
        if [[ ! -f "$codium_path" ]]; then
            add_finding "INFO" "editor" \
                "Using VS Code instead of VSCodium" \
                "$settings_path" \
                "VS Code (Microsoft build)" \
                "VS Code includes Microsoft-specific telemetry and proprietary extensions marketplace. VSCodium is a community build with telemetry stripped out." \
                "Consider switching to VSCodium (vscodium.com)" \
                "Some Microsoft-proprietary extensions (Remote SSH, Live Share) are not available on VSCodium's marketplace." \
                ""
        fi
    fi
}

_check_vscode_extensions() {
    # Check for extensions known to have telemetry
    local code_cmd=""
    if has_command code; then
        code_cmd="code"
    elif has_command codium; then
        code_cmd="codium"
    fi

    [[ -z "$code_cmd" ]] && return

    local telemetry_extensions=(
        "GitHub.copilot"
        "GitHub.copilot-chat"
        "ms-python.python"
        "ms-vscode.cpptools"
        "ms-toolsai.jupyter"
    )

    local installed
    installed="$($code_cmd --list-extensions 2>/dev/null)" || return

    local found_extensions=""
    for ext in "${telemetry_extensions[@]}"; do
        if echo "$installed" | grep -qi "$ext"; then
            found_extensions+="${ext}, "
        fi
    done

    if [[ -n "$found_extensions" ]]; then
        found_extensions="${found_extensions%, }"
        add_finding "HIGH" "editor" \
            "VS Code extensions with known telemetry installed" \
            "" \
            "Installed: ${found_extensions}" \
            "These extensions are known to send usage data, code snippets, or file metadata to their vendors. GitHub Copilot in particular transmits code context to GitHub/Microsoft servers." \
            "Review each extension and disable/remove those not needed. Consider privacy-focused alternatives." \
            "Removing Copilot means losing AI code completion. Removing MS Python means losing some Python tooling (alternatives exist)." \
            ""
    fi
}

_check_jetbrains_telemetry() {
    # JetBrains stores preferences in ~/Library/Application Support/JetBrains/<product>/options/
    local jetbrains_base=""
    if is_macos; then
        jetbrains_base="${HOME}/Library/Application Support/JetBrains"
    elif is_linux; then
        jetbrains_base="${HOME}/.config/JetBrains"
    fi

    [[ ! -d "$jetbrains_base" ]] && return

    # Look for any JetBrains product directory
    local found_product=false
    for product_dir in "${jetbrains_base}"/*/; do
        [[ ! -d "$product_dir" ]] && continue
        found_product=true

        local usage_stats="${product_dir}options/usage.statistics.xml"
        local other_xml="${product_dir}options/other.xml"

        # Check if data sharing is explicitly disabled
        local sharing_disabled=false
        if [[ -f "$usage_stats" ]]; then
            if grep -q 'name="allowed".*value="false"' "$usage_stats" 2>/dev/null; then
                sharing_disabled=true
            fi
        fi

        if [[ "$sharing_disabled" == false ]]; then
            local product_name
            product_name="$(basename "$product_dir")"
            add_finding "MEDIUM" "editor" \
                "JetBrains ${product_name} data sharing may be enabled" \
                "${product_dir}options/" \
                "usage.statistics.xml not found or sharing not disabled" \
                "JetBrains IDEs can send usage statistics, feature usage data, and plugin information to JetBrains servers." \
                "Disable data sharing in IDE: Settings → Appearance & Behavior → System Settings → Data Sharing" \
                "You lose contributing to JetBrains product improvement data. No impact on IDE functionality." \
                ""
        fi
        break  # Only report once
    done
}

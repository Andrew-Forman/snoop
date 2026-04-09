#!/usr/bin/env bash
# snoop — Git & version control checks

run_git_checks() {
    _check_git_credential_helper
    _check_gitconfig_includes
    _check_github_cli
}

_check_git_credential_helper() {
    has_command git || return

    local cred_helper
    cred_helper="$(git config --global credential.helper 2>/dev/null || echo "")"

    if [[ "$cred_helper" == "store" ]]; then
        add_finding "HIGH" "git" \
            "Git credentials stored in plaintext" \
            "${HOME}/.git-credentials" \
            "credential.helper = store" \
            "The 'store' credential helper saves passwords and tokens in plaintext in ~/.git-credentials. Anyone with read access to your home directory can extract them." \
            "Switch to an encrypted credential helper (osxkeychain on macOS, libsecret on Linux)" \
            "None — encrypted helpers work identically from the user's perspective." \
            "remediate_git_credential_helper"
    elif [[ -z "$cred_helper" ]]; then
        add_finding "LOW" "git" \
            "No Git credential helper configured" \
            "${HOME}/.gitconfig" \
            "credential.helper = (not set)" \
            "Without a credential helper, Git will prompt for credentials each time or you may end up storing them insecurely." \
            "Configure an encrypted credential helper" \
            "None." \
            "remediate_git_credential_helper"
    fi
}

_check_gitconfig_includes() {
    local gitconfig="${HOME}/.gitconfig"
    [[ ! -f "$gitconfig" ]] && return

    local includes
    includes="$(grep -i '^\[include\]' "$gitconfig" 2>/dev/null || true)"
    local include_paths
    include_paths="$(grep -i 'path[[:space:]]*=' "$gitconfig" 2>/dev/null | grep -v '^#' || true)"

    if [[ -n "$include_paths" ]]; then
        add_finding "MEDIUM" "git" \
            "Git config includes external files" \
            "$gitconfig" \
            "$(echo "$include_paths" | head -3)" \
            "External includes in .gitconfig can inject hooks, aliases, or credential settings. Verify these are intentional and from trusted sources." \
            "Review each included file and remove any unrecognized entries" \
            "Removing legitimate includes may break your Git workflow." \
            ""
    fi
}

_check_github_cli() {
    has_command gh || return

    local auth_status
    auth_status="$(gh auth status 2>&1 || true)"

    if echo "$auth_status" | grep -q "Logged in"; then
        local scopes
        scopes="$(echo "$auth_status" | grep -o 'Token scopes:.*' | head -1 || true)"

        add_finding "LOW" "git" \
            "GitHub CLI is authenticated" \
            "${HOME}/.config/gh/hosts.yml" \
            "$(echo "$auth_status" | grep 'Logged in' | head -1 | sed 's/^[[:space:]]*//')" \
            "The gh CLI has an active authentication token. Review the token scopes to ensure it has only the permissions you need." \
            "Review token scopes with 'gh auth status' and regenerate with minimal scopes if needed" \
            "Reducing scopes may limit some gh CLI operations." \
            ""
    fi
}

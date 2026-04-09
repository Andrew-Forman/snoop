#!/usr/bin/env bash
# snoop — Secrets & credentials checks

run_secrets_checks() {
    _check_env_files
    _check_shell_history_secrets
    _check_ssh_keys
    _check_aws_credentials
    _check_netrc
}

_check_env_files() {
    local scan_dirs=("${SCAN_PATH}")

    # Also check common dev directories if scan_path is home
    if [[ "$SCAN_PATH" == "$HOME" ]]; then
        for d in code projects dev src repos workspace; do
            [[ -d "${HOME}/${d}" ]] && scan_dirs+=("${HOME}/${d}")
        done
    fi

    local env_files=()
    for dir in "${scan_dirs[@]}"; do
        while IFS= read -r -d '' f; do
            env_files+=("$f")
        done < <(find "$dir" -maxdepth 4 -name ".env" -o -name ".env.local" -o -name ".env.production" -o -name ".env.development" 2>/dev/null | head -20 | tr '\n' '\0')
    done

    if [[ ${#env_files[@]} -gt 0 ]]; then
        local file_list=""
        local has_secrets=false
        for f in "${env_files[@]}"; do
            [[ -z "$f" ]] && continue
            # Check for likely secrets
            if grep -qE '(API_KEY|SECRET|TOKEN|PASSWORD|PRIVATE_KEY|AWS_|STRIPE_|DATABASE_URL)' "$f" 2>/dev/null; then
                has_secrets=true
                local count
                count="$(grep -cE '(API_KEY|SECRET|TOKEN|PASSWORD|PRIVATE_KEY|AWS_|STRIPE_|DATABASE_URL)' "$f" 2>/dev/null || echo 0)"
                file_list+="  ${f} (${count} potential secrets)\n"
            fi
        done

        if [[ "$has_secrets" == true ]]; then
            add_finding "CRITICAL" "secrets" \
                "Plaintext .env files with secrets found" \
                "Multiple locations" \
                "$(echo -e "$file_list" | head -5)" \
                "API keys, tokens, and passwords stored in plaintext .env files can be accidentally committed to Git, exposed in backups, or read by any process running as your user." \
                "Use a secrets manager (pass, sops, 1Password CLI, or Doppler) instead of plaintext .env files" \
                "Requires setting up a secrets manager and updating your development workflow to pull secrets from it." \
                ""
        fi
    fi
}

_check_shell_history_secrets() {
    local history_files=()
    [[ -f "${HOME}/.bash_history" ]] && history_files+=("${HOME}/.bash_history")
    [[ -f "${HOME}/.zsh_history" ]] && history_files+=("${HOME}/.zsh_history")

    for hist in "${history_files[@]}"; do
        local matches
        matches="$(grep -cE '(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[A-Z0-9]{16}|xox[baprs]-[a-zA-Z0-9-]{10,}|glpat-[a-zA-Z0-9_-]{20,}|-----BEGIN)' "$hist" 2>/dev/null || echo "0")"
        matches="$(echo "$matches" | tr -d '[:space:]')"

        if [[ "$matches" -gt 0 ]]; then
            add_finding "HIGH" "secrets" \
                "Secrets found in shell history" \
                "$hist" \
                "${matches} lines matching secret patterns" \
                "Shell history can contain API keys, tokens, and passwords from commands like curl, export, or direct CLI usage. This history is stored in plaintext." \
                "Remove sensitive lines from history. Add HISTIGNORE patterns to prevent future leaks." \
                "None — cleaning history doesn't affect functionality." \
                "remediate_shell_history"
        fi
    done
}

_check_ssh_keys() {
    local ssh_dir="${HOME}/.ssh"
    [[ ! -d "$ssh_dir" ]] && return

    for key in "${ssh_dir}"/id_*; do
        [[ ! -f "$key" ]] && continue
        # Skip public keys
        [[ "$key" == *.pub ]] && continue

        # Check if the key has a passphrase
        # ssh-keygen -y -P "" will fail if there IS a passphrase
        if ssh-keygen -y -P "" -f "$key" &>/dev/null; then
            add_finding "MEDIUM" "secrets" \
                "SSH private key without passphrase" \
                "$key" \
                "No passphrase set" \
                "If this key is stolen (malware, disk theft, backup exposure), it can be used immediately without any additional authentication." \
                "Add a passphrase with: ssh-keygen -p -f ${key}" \
                "You'll need to enter the passphrase when using the key (ssh-agent can cache it)." \
                ""
        fi
    done
}

_check_aws_credentials() {
    local aws_creds="${HOME}/.aws/credentials"
    [[ ! -f "$aws_creds" ]] && return

    if grep -q 'aws_secret_access_key' "$aws_creds" 2>/dev/null; then
        add_finding "HIGH" "secrets" \
            "AWS credentials stored in plaintext" \
            "$aws_creds" \
            "Plaintext access keys found" \
            "Static AWS credentials in ~/.aws/credentials can be exfiltrated by malware or exposed in backups. They often have broad permissions." \
            "Switch to AWS SSO (aws configure sso), IAM Identity Center, or environment-based auth with short-lived tokens" \
            "Requires setting up AWS SSO or similar. Slightly more complex initial setup." \
            ""
    fi
}

_check_netrc() {
    local netrc="${HOME}/.netrc"
    [[ ! -f "$netrc" ]] && return

    add_finding "HIGH" "secrets" \
        "Plaintext credentials in .netrc" \
        "$netrc" \
        "$(wc -l < "$netrc" | tr -d ' ') lines" \
        ".netrc contains plaintext login credentials for HTTP services. Any process running as your user can read them." \
        "Remove .netrc and use per-tool credential helpers instead" \
        "Tools relying on .netrc for auth will need alternative configuration." \
        ""
}

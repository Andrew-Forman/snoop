#!/usr/bin/env bash
#
# snoop test harness
#
# Creates mock config files in a temp directory, overrides HOME,
# sources snoop modules, runs checks, and asserts findings.
#
# Usage: ./tests/run_tests.sh
#
# No dependencies. Returns exit code 0 if all tests pass, 1 if any fail.

set -uo pipefail

# ─── Test Framework ────────────────────────────────────────────────────────────

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAIL_MESSAGES=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
DIM='\033[0;90m'
RESET='\033[0m'

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${RESET} ${label}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAIL_MESSAGES+=("${label}: expected '${expected}', got '${actual}'")
        echo -e "  ${RED}✗${RESET} ${label}"
        echo -e "    ${DIM}expected: ${expected}${RESET}"
        echo -e "    ${DIM}  actual: ${actual}${RESET}"
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -q "$needle"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${RESET} ${label}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAIL_MESSAGES+=("${label}: '${needle}' not found in output")
        echo -e "  ${RED}✗${RESET} ${label}"
        echo -e "    ${DIM}expected to contain: ${needle}${RESET}"
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! echo "$haystack" | grep -q "$needle"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${RESET} ${label}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAIL_MESSAGES+=("${label}: '${needle}' should not be present in output")
        echo -e "  ${RED}✗${RESET} ${label}"
        echo -e "    ${DIM}should not contain: ${needle}${RESET}"
    fi
}

assert_file_exists() {
    local label="$1" path="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$path" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${RESET} ${label}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAIL_MESSAGES+=("${label}: file not found at ${path}")
        echo -e "  ${RED}✗${RESET} ${label}"
    fi
}

assert_finding_count() {
    local label="$1" expected="$2"
    local actual="${#FINDINGS[@]}"
    assert_eq "$label" "$expected" "$actual"
}

# Get severity of finding at index
finding_severity() {
    echo "${FINDINGS[$1]}" | cut -d'|' -f1
}

# Get title of finding at index
finding_title() {
    echo "${FINDINGS[$1]}" | cut -d'|' -f3
}

# Get category of finding at index
finding_category() {
    echo "${FINDINGS[$1]}" | cut -d'|' -f2
}

# Get fix_func of finding at index
finding_fix_func() {
    echo "${FINDINGS[$1]}" | cut -d'|' -f9
}

# ─── Test Environment Setup ───────────────────────────────────────────────────

SNOOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOCK_HOME=""
REAL_HOME="$HOME"

setup_mock_home() {
    MOCK_HOME="$(mktemp -d)"
    export HOME="$MOCK_HOME"
    FINDINGS=()
}

teardown_mock_home() {
    if [[ -n "$MOCK_HOME" && -d "$MOCK_HOME" ]]; then
        rm -rf "$MOCK_HOME"
    fi
    MOCK_HOME=""
    export HOME="$REAL_HOME"
}

# Source snoop libraries (but not the main entry point which calls main())
source_snoop_libs() {
    source "${SNOOP_DIR}/lib/utils.sh"
    source "${SNOOP_DIR}/lib/output.sh"
    source "${SNOOP_DIR}/lib/interactive.sh"

    source "${SNOOP_DIR}/lib/checks/editor.sh"
    source "${SNOOP_DIR}/lib/checks/git.sh"
    source "${SNOOP_DIR}/lib/checks/secrets.sh"
    source "${SNOOP_DIR}/lib/checks/system.sh"
    source "${SNOOP_DIR}/lib/checks/apps.sh"
    source "${SNOOP_DIR}/lib/checks/network.sh"
    source "${SNOOP_DIR}/lib/checks/deps.sh"

    source "${SNOOP_DIR}/lib/remediate/editor.sh"
    source "${SNOOP_DIR}/lib/remediate/git.sh"
    source "${SNOOP_DIR}/lib/remediate/secrets.sh"
    source "${SNOOP_DIR}/lib/remediate/system.sh"
    source "${SNOOP_DIR}/lib/remediate/apps.sh"

    detect_os
}

# ─── Mock Helpers ──────────────────────────────────────────────────────────────

# Create a VS Code settings.json with telemetry ON
create_vscode_settings_telemetry_on() {
    local settings_dir
    if is_macos; then
        settings_dir="${HOME}/Library/Application Support/Code/User"
    else
        settings_dir="${HOME}/.config/Code/User"
    fi
    mkdir -p "$settings_dir"
    cat > "${settings_dir}/settings.json" <<'JSON'
{
    "editor.fontSize": 14,
    "telemetry.telemetryLevel": "all",
    "workbench.enableExperiments": true,
    "workbench.settings.enableNaturalLanguageSearch": true
}
JSON
}

# Create a VS Code settings.json with telemetry OFF
create_vscode_settings_telemetry_off() {
    local settings_dir
    if is_macos; then
        settings_dir="${HOME}/Library/Application Support/Code/User"
    else
        settings_dir="${HOME}/.config/Code/User"
    fi
    mkdir -p "$settings_dir"
    cat > "${settings_dir}/settings.json" <<'JSON'
{
    "editor.fontSize": 14,
    "telemetry.telemetryLevel": "off",
    "workbench.enableExperiments": false,
    "workbench.settings.enableNaturalLanguageSearch": false
}
JSON
}

# Create a Cursor settings.json with telemetry ON
create_cursor_settings_telemetry_on() {
    local settings_dir
    if is_macos; then
        settings_dir="${HOME}/Library/Application Support/Cursor/User"
    else
        settings_dir="${HOME}/.config/Cursor/User"
    fi
    mkdir -p "$settings_dir"
    cat > "${settings_dir}/settings.json" <<'JSON'
{
    "editor.fontSize": 14,
    "telemetry.telemetryLevel": "all"
}
JSON
}

# Create a .env file with fake secrets
create_dotenv_with_secrets() {
    local dir="${1:-$HOME/projects/myapp}"
    mkdir -p "$dir"
    cat > "${dir}/.env" <<'ENV'
DATABASE_URL=postgres://user:password@localhost:5432/mydb
STRIPE_SK=sk_live_abc123def456
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
TINFOIL_API_KEY=tf_key_secretvalue
HARMLESS_SETTING=true
ENV
}

# Create a .env file with no secrets
create_dotenv_no_secrets() {
    local dir="${1:-$HOME/projects/myapp}"
    mkdir -p "$dir"
    cat > "${dir}/.env" <<'ENV'
NODE_ENV=development
PORT=3000
LOG_LEVEL=debug
ENV
}

# Create shell history with leaked secrets
create_shell_history_with_secrets() {
    cat > "${HOME}/.zsh_history" <<'HIST'
ls -la
cd ~/projects
export OPENAI_API_KEY=sk-abc123456789012345678901
git push origin main
curl -H "Authorization: Bearer ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" https://api.github.com
HIST
}

# Create clean shell history
create_shell_history_clean() {
    cat > "${HOME}/.zsh_history" <<'HIST'
ls -la
cd ~/projects
git status
npm install
HIST
}

# Create SSH key without passphrase (real key so ssh-keygen can parse it)
create_ssh_key_no_passphrase() {
    mkdir -p "${HOME}/.ssh"
    ssh-keygen -t ed25519 -f "${HOME}/.ssh/id_ed25519" -N "" -q -C "test@snoop"
}

# Create AWS credentials file
create_aws_credentials() {
    mkdir -p "${HOME}/.aws"
    cat > "${HOME}/.aws/credentials" <<'AWS'
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS
}

# Create .netrc file
create_netrc() {
    cat > "${HOME}/.netrc" <<'NETRC'
machine github.com
  login user
  password ghp_exampletoken123
NETRC
}

# Create npmrc with telemetry not disabled
create_npmrc_telemetry_on() {
    cat > "${HOME}/.npmrc" <<'NPMRC'
registry=https://registry.npmjs.org/
NPMRC
}

# Create npmrc with telemetry disabled
create_npmrc_telemetry_off() {
    cat > "${HOME}/.npmrc" <<'NPMRC'
registry=https://registry.npmjs.org/
update-notifier=false
audit=false
fund=false
NPMRC
}

# Create git config with plaintext credential store
create_git_credential_store_plaintext() {
    cat > "${HOME}/.gitconfig" <<'GIT'
[user]
    name = Test User
    email = test@example.com
[credential]
    helper = store
GIT
}

# Create git config with encrypted credential store
create_git_credential_store_encrypted() {
    cat > "${HOME}/.gitconfig" <<'GIT'
[user]
    name = Test User
    email = test@example.com
[credential]
    helper = osxkeychain
GIT
}

# Create git config with includes
create_git_config_with_includes() {
    cat > "${HOME}/.gitconfig" <<'GIT'
[user]
    name = Test User
    email = test@example.com
[include]
    path = ~/.gitconfig.work
[credential]
    helper = osxkeychain
GIT
}

# ─── Test Suites ───────────────────────────────────────────────────────────────

# ── Core Plumbing ──────────────────────────────────────────────────────────────

test_add_finding_format() {
    echo -e "\n${YELLOW}▸ add_finding record format${RESET}"
    setup_mock_home

    add_finding "HIGH" "editor" "Test title" "/path/file" "current val" "risk text" "fix text" "tradeoff text" "fix_func_name"

    assert_finding_count "registers exactly one finding" "1"
    assert_eq "severity is HIGH" "HIGH" "$(finding_severity 0)"
    assert_eq "category is editor" "editor" "$(finding_category 0)"
    assert_eq "title is correct" "Test title" "$(finding_title 0)"
    assert_eq "fix_func is correct" "fix_func_name" "$(finding_fix_func 0)"

    # Verify all 9 fields are present
    local field_count
    field_count="$(echo "${FINDINGS[0]}" | awk -F'|' '{print NF}')"
    assert_eq "record has 9 pipe-delimited fields" "9" "$field_count"

    teardown_mock_home
}

test_add_finding_optional_fields() {
    echo -e "\n${YELLOW}▸ add_finding with empty optional fields${RESET}"
    setup_mock_home

    add_finding "INFO" "deps" "Informational only" "" "" "some risk" "" "" ""

    assert_finding_count "registers one finding" "1"
    assert_eq "severity is INFO" "INFO" "$(finding_severity 0)"
    assert_eq "fix_func is empty" "" "$(finding_fix_func 0)"

    teardown_mock_home
}

test_should_run_category_defaults() {
    echo -e "\n${YELLOW}▸ should_run_category — default (all enabled)${RESET}"

    ONLY_CATEGORIES=""
    SKIP_CATEGORIES=""

    should_run_category "editor" && local editor_result="yes" || local editor_result="no"
    should_run_category "secrets" && local secrets_result="yes" || local secrets_result="no"
    should_run_category "network" && local network_result="yes" || local network_result="no"

    assert_eq "editor runs by default" "yes" "$editor_result"
    assert_eq "secrets runs by default" "yes" "$secrets_result"
    assert_eq "network runs by default" "yes" "$network_result"
}

test_should_run_category_only() {
    echo -e "\n${YELLOW}▸ should_run_category — --only filter${RESET}"

    ONLY_CATEGORIES="editor,secrets"
    SKIP_CATEGORIES=""

    should_run_category "editor" && local r1="yes" || local r1="no"
    should_run_category "secrets" && local r2="yes" || local r2="no"
    should_run_category "network" && local r3="yes" || local r3="no"
    should_run_category "apps" && local r4="yes" || local r4="no"

    assert_eq "--only includes editor" "yes" "$r1"
    assert_eq "--only includes secrets" "yes" "$r2"
    assert_eq "--only excludes network" "no" "$r3"
    assert_eq "--only excludes apps" "no" "$r4"

    ONLY_CATEGORIES=""
}

test_should_run_category_skip() {
    echo -e "\n${YELLOW}▸ should_run_category — --skip filter${RESET}"

    ONLY_CATEGORIES=""
    SKIP_CATEGORIES="network,deps"

    should_run_category "editor" && local r1="yes" || local r1="no"
    should_run_category "network" && local r2="yes" || local r2="no"
    should_run_category "deps" && local r3="yes" || local r3="no"

    assert_eq "--skip keeps editor" "yes" "$r1"
    assert_eq "--skip removes network" "no" "$r2"
    assert_eq "--skip removes deps" "no" "$r3"

    SKIP_CATEGORIES=""
}

# ── Editor Checks ─────────────────────────────────────────────────────────────

test_editor_check_telemetry_on() {
    echo -e "\n${YELLOW}▸ editor check — VS Code telemetry enabled${RESET}"
    setup_mock_home
    create_vscode_settings_telemetry_on

    run_editor_checks

    # Should find telemetry-related issues
    local found_telemetry=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "telemetry"; then
            found_telemetry=true
            break
        fi
    done

    assert_eq "detects VS Code telemetry" "true" "$found_telemetry"

    # Check severity is HIGH for telemetry
    local telemetry_severity=""
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "telemetry is enabled"; then
            telemetry_severity="$(echo "$finding" | cut -d'|' -f1)"
            break
        fi
    done

    if [[ -n "$telemetry_severity" ]]; then
        assert_eq "telemetry finding is HIGH severity" "HIGH" "$telemetry_severity"
    fi

    teardown_mock_home
}

test_editor_check_telemetry_off() {
    echo -e "\n${YELLOW}▸ editor check — VS Code telemetry disabled${RESET}"
    setup_mock_home
    create_vscode_settings_telemetry_off

    run_editor_checks

    # Should NOT find telemetry level finding, experiments, or NLS
    local found_telemetry_issue=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "telemetry is enabled\|experiments enabled\|natural language"; then
            found_telemetry_issue=true
            break
        fi
    done

    assert_eq "no telemetry/experiments/NLS finding when all disabled" "false" "$found_telemetry_issue"

    teardown_mock_home
}

test_editor_check_cursor_telemetry() {
    echo -e "\n${YELLOW}▸ editor check — Cursor telemetry enabled${RESET}"
    setup_mock_home
    create_cursor_settings_telemetry_on

    run_editor_checks

    local found_cursor=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "cursor.*telemetry"; then
            found_cursor=true
            break
        fi
    done

    assert_eq "detects Cursor telemetry" "true" "$found_cursor"

    teardown_mock_home
}

test_editor_no_settings_file() {
    echo -e "\n${YELLOW}▸ editor check — no settings file exists${RESET}"
    setup_mock_home
    # Don't create any settings files

    run_editor_checks

    # Should produce zero findings (no editor config to scan)
    assert_finding_count "no findings when no editor config exists" "0"

    teardown_mock_home
}

# ── Secrets Checks ────────────────────────────────────────────────────────────

test_secrets_dotenv_with_keys() {
    echo -e "\n${YELLOW}▸ secrets check — .env file with API keys${RESET}"
    setup_mock_home
    SCAN_PATH="${HOME}"
    create_dotenv_with_secrets "${HOME}/projects/myapp"

    run_secrets_checks

    local found_env=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "\.env\|plaintext.*secret\|env.*file"; then
            found_env=true
            break
        fi
    done

    assert_eq "detects .env with secrets" "true" "$found_env"

    # Verify severity is CRITICAL
    local env_sev=""
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "\.env"; then
            env_sev="${finding%%|*}"
            break
        fi
    done
    [[ -n "$env_sev" ]] && assert_eq ".env secrets are CRITICAL severity" "CRITICAL" "$env_sev"

    teardown_mock_home
}

test_secrets_dotenv_no_secrets() {
    echo -e "\n${YELLOW}▸ secrets check — .env file without secrets${RESET}"
    setup_mock_home
    SCAN_PATH="${HOME}"
    create_dotenv_no_secrets "${HOME}/projects/myapp"

    run_secrets_checks

    local found_env=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "\.env\|plaintext.*secret"; then
            found_env=true
            break
        fi
    done

    assert_eq "no finding for .env without secrets" "false" "$found_env"

    teardown_mock_home
}

test_secrets_shell_history() {
    echo -e "\n${YELLOW}▸ secrets check — shell history with API keys${RESET}"
    setup_mock_home
    SCAN_PATH="${HOME}"
    create_shell_history_with_secrets

    run_secrets_checks

    local found_history=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "history"; then
            found_history=true
            break
        fi
    done

    assert_eq "detects secrets in shell history" "true" "$found_history"

    teardown_mock_home
}

test_secrets_shell_history_clean() {
    echo -e "\n${YELLOW}▸ secrets check — clean shell history${RESET}"
    setup_mock_home
    SCAN_PATH="${HOME}"
    create_shell_history_clean

    run_secrets_checks

    local found_history=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "history"; then
            found_history=true
            break
        fi
    done

    assert_eq "no finding for clean shell history" "false" "$found_history"

    teardown_mock_home
}

test_secrets_aws_credentials() {
    echo -e "\n${YELLOW}▸ secrets check — AWS credentials file${RESET}"
    setup_mock_home
    SCAN_PATH="${HOME}"
    create_aws_credentials

    run_secrets_checks

    local found_aws=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "aws"; then
            found_aws=true
            break
        fi
    done

    assert_eq "detects AWS credentials file" "true" "$found_aws"

    teardown_mock_home
}

test_secrets_ssh_key() {
    echo -e "\n${YELLOW}▸ secrets check — SSH key without passphrase${RESET}"
    setup_mock_home
    SCAN_PATH="${HOME}"
    create_ssh_key_no_passphrase

    run_secrets_checks

    local found_ssh=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "ssh"; then
            found_ssh=true
            break
        fi
    done

    assert_eq "detects SSH key without passphrase" "true" "$found_ssh"

    teardown_mock_home
}

test_secrets_netrc() {
    echo -e "\n${YELLOW}▸ secrets check — .netrc with credentials${RESET}"
    setup_mock_home
    SCAN_PATH="${HOME}"
    create_netrc

    run_secrets_checks

    local found_netrc=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "netrc"; then
            found_netrc=true
            break
        fi
    done

    assert_eq "detects .netrc file" "true" "$found_netrc"

    teardown_mock_home
}

test_secrets_scan_path_scoping() {
    echo -e "\n${YELLOW}▸ secrets check — --scan-path scopes the search${RESET}"
    setup_mock_home

    # Put secrets in a dir that is NOT under SCAN_PATH
    create_dotenv_with_secrets "${HOME}/outside/project"

    # Point SCAN_PATH at an empty dir
    mkdir -p "${HOME}/scoped"
    SCAN_PATH="${HOME}/scoped"

    run_secrets_checks

    local found_env=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "\.env\|plaintext.*secret"; then
            found_env=true
            break
        fi
    done

    assert_eq "does not find .env outside scan-path" "false" "$found_env"

    SCAN_PATH="${HOME}"
    teardown_mock_home
}

# ── Git Checks ────────────────────────────────────────────────────────────────

test_git_credential_plaintext() {
    echo -e "\n${YELLOW}▸ git check — plaintext credential store${RESET}"
    setup_mock_home
    create_git_credential_store_plaintext

    run_git_checks

    local found_cred=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "credential.*plaintext\|plaintext.*credential\|credentials stored in plaintext"; then
            found_cred=true
            break
        fi
    done

    assert_eq "detects plaintext git credential store" "true" "$found_cred"

    teardown_mock_home
}

test_git_credential_encrypted() {
    echo -e "\n${YELLOW}▸ git check — encrypted credential store${RESET}"
    setup_mock_home
    create_git_credential_store_encrypted

    run_git_checks

    local found_plaintext_cred=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "plaintext.*credential\|credentials stored in plaintext"; then
            found_plaintext_cred=true
            break
        fi
    done

    assert_eq "no plaintext credential finding with osxkeychain" "false" "$found_plaintext_cred"

    teardown_mock_home
}

test_git_config_includes() {
    echo -e "\n${YELLOW}▸ git check — gitconfig with includes${RESET}"
    setup_mock_home
    create_git_config_with_includes

    run_git_checks

    local found_includes=false
    for finding in "${FINDINGS[@]}"; do
        if echo "$finding" | grep -qi "include"; then
            found_includes=true
            break
        fi
    done

    assert_eq "detects gitconfig includes" "true" "$found_includes"

    teardown_mock_home
}

# ── Output ────────────────────────────────────────────────────────────────────

test_json_output_valid() {
    echo -e "\n${YELLOW}▸ JSON output — valid parseable JSON${RESET}"
    setup_mock_home

    add_finding "HIGH" "editor" "Test finding" "/tmp/test" "current" "risk" "fix" "tradeoff" "fix_func"
    add_finding "LOW" "apps" "Another finding" "" "val" "risk2" "fix2" "trade2" ""

    local json_out
    json_out="$(output_json 2>/dev/null)"

    # output_json produces a flat array: [{...}, {...}]
    if has_command jq; then
        local valid
        echo "$json_out" | jq . > /dev/null 2>&1 && valid="yes" || valid="no"
        assert_eq "JSON output is valid" "yes" "$valid"

        local count
        count="$(echo "$json_out" | jq 'length' 2>/dev/null || echo "0")"
        assert_eq "JSON array contains 2 findings" "2" "$count"

        # Check field values
        local first_sev
        first_sev="$(echo "$json_out" | jq -r '.[0].severity' 2>/dev/null)"
        assert_eq "first finding severity is HIGH" "HIGH" "$first_sev"

        local second_auto
        second_auto="$(echo "$json_out" | jq -r '.[1].auto_fixable' 2>/dev/null)"
        assert_eq "second finding not auto-fixable" "false" "$second_auto"
    else
        # Fallback: just check structure
        assert_contains "JSON has severity field" '"severity"' "$json_out"
        assert_contains "JSON has category field" '"category"' "$json_out"
    fi

    teardown_mock_home
}

test_json_output_empty() {
    echo -e "\n${YELLOW}▸ JSON output — empty findings${RESET}"
    setup_mock_home

    local json_out
    json_out="$(output_json 2>/dev/null)"

    if has_command jq; then
        local valid
        echo "$json_out" | jq . > /dev/null 2>&1 && valid="yes" || valid="no"
        assert_eq "empty JSON output is valid" "yes" "$valid"

        local count
        count="$(echo "$json_out" | jq 'length' 2>/dev/null || echo "0")"
        assert_eq "empty JSON has 0 findings" "0" "$count"
    else
        assert_contains "empty JSON is an array" '\[' "$json_out"
    fi

    teardown_mock_home
}

test_text_report_output() {
    echo -e "\n${YELLOW}▸ text report — contains expected sections${RESET}"
    setup_mock_home

    add_finding "CRITICAL" "system" "Disk not encrypted" "" "" "risk" "fix" "" ""
    add_finding "LOW" "apps" "Minor issue" "" "" "risk" "" "" ""

    local report_out
    report_out="$(output_report 2>/dev/null)"

    assert_contains "report has header" "snoop" "$report_out"
    assert_contains "report shows CRITICAL" "CRITICAL" "$report_out"
    assert_contains "report shows LOW" "LOW" "$report_out"
    assert_contains "report shows finding title" "Disk not encrypted" "$report_out"

    teardown_mock_home
}

# ── Exit Codes ────────────────────────────────────────────────────────────────

test_exit_code_with_critical() {
    echo -e "\n${YELLOW}▸ exit codes — CRITICAL finding present${RESET}"
    setup_mock_home

    add_finding "CRITICAL" "system" "Disk not encrypted" "" "" "" "" "" ""

    local has_critical=false
    for finding in "${FINDINGS[@]}"; do
        local sev="${finding%%|*}"
        if [[ "$sev" == "CRITICAL" || "$sev" == "HIGH" ]]; then
            has_critical=true
            break
        fi
    done

    assert_eq "CRITICAL finding triggers exit 1 path" "true" "$has_critical"

    teardown_mock_home
}

test_exit_code_with_high() {
    echo -e "\n${YELLOW}▸ exit codes — HIGH finding present${RESET}"
    setup_mock_home

    add_finding "HIGH" "editor" "Telemetry on" "" "" "" "" "" ""
    add_finding "LOW" "apps" "Minor" "" "" "" "" "" ""

    local has_critical=false
    for finding in "${FINDINGS[@]}"; do
        local sev="${finding%%|*}"
        if [[ "$sev" == "CRITICAL" || "$sev" == "HIGH" ]]; then
            has_critical=true
            break
        fi
    done

    assert_eq "HIGH finding triggers exit 1 path" "true" "$has_critical"

    teardown_mock_home
}

test_exit_code_clean() {
    echo -e "\n${YELLOW}▸ exit codes — only LOW/INFO findings${RESET}"
    setup_mock_home

    add_finding "LOW" "apps" "Minor issue" "" "" "" "" "" ""
    add_finding "INFO" "deps" "Informational" "" "" "" "" "" ""

    local has_critical=false
    for finding in "${FINDINGS[@]}"; do
        local sev="${finding%%|*}"
        if [[ "$sev" == "CRITICAL" || "$sev" == "HIGH" ]]; then
            has_critical=true
            break
        fi
    done

    assert_eq "LOW/INFO only does not trigger exit 1" "false" "$has_critical"

    teardown_mock_home
}

test_exit_code_no_findings() {
    echo -e "\n${YELLOW}▸ exit codes — zero findings${RESET}"
    setup_mock_home

    local has_critical=false
    for finding in "${FINDINGS[@]}"; do
        local sev="${finding%%|*}"
        if [[ "$sev" == "CRITICAL" || "$sev" == "HIGH" ]]; then
            has_critical=true
            break
        fi
    done

    assert_eq "no findings does not trigger exit 1" "false" "$has_critical"

    teardown_mock_home
}

# ── Remediation Safety ────────────────────────────────────────────────────────

test_backup_creation() {
    echo -e "\n${YELLOW}▸ remediation — backup created before modification${RESET}"
    setup_mock_home

    local test_file="${HOME}/test_config.json"
    echo '{"setting": "original"}' > "$test_file"

    backup_file "$test_file"

    local backup_found=false
    for f in "${HOME}"/test_config.json.snoop.bak.*; do
        if [[ -f "$f" ]]; then
            backup_found=true
            local backup_content
            backup_content="$(cat "$f")"
            assert_eq "backup preserves original content" '{"setting": "original"}' "$backup_content"
            break
        fi
    done

    assert_eq "backup file created with .snoop.bak suffix" "true" "$backup_found"

    teardown_mock_home
}

test_backup_nonexistent_file() {
    echo -e "\n${YELLOW}▸ remediation — backup of nonexistent file is a no-op${RESET}"
    setup_mock_home

    # Should not error
    backup_file "${HOME}/does_not_exist.json"

    local backup_found=false
    for f in "${HOME}"/does_not_exist.json.snoop.bak.*; do
        if [[ -f "$f" ]]; then
            backup_found=true
            break
        fi
    done

    assert_eq "no backup created for nonexistent file" "false" "$backup_found"

    teardown_mock_home
}

test_remediate_vscode_telemetry() {
    echo -e "\n${YELLOW}▸ remediation — VS Code telemetry fix changes file${RESET}"
    setup_mock_home
    create_vscode_settings_telemetry_on

    local settings_path
    settings_path="$(get_vscode_settings_path "code")"

    # Apply the remediation
    remediate_vscode_telemetry_level "$settings_path" > /dev/null 2>&1

    # Check the file was modified
    local new_level
    new_level="$(json_get_nested "$settings_path" "telemetry.telemetryLevel")"

    assert_eq "telemetry level set to off after remediation" "off" "$new_level"

    # Verify backup was created
    local backup_found=false
    local dir
    dir="$(dirname "$settings_path")"
    for f in "${dir}"/settings.json.snoop.bak.*; do
        if [[ -f "$f" ]]; then
            backup_found=true
            break
        fi
    done
    assert_eq "backup created during remediation" "true" "$backup_found"

    teardown_mock_home
}

test_remediate_vscode_experiments() {
    echo -e "\n${YELLOW}▸ remediation — VS Code experiments fix changes file${RESET}"
    setup_mock_home
    create_vscode_settings_telemetry_on

    local settings_path
    settings_path="$(get_vscode_settings_path "code")"

    remediate_vscode_experiments "$settings_path" > /dev/null 2>&1

    local new_val
    if has_command jq; then
        new_val="$(jq -r '."workbench.enableExperiments"' "$settings_path" 2>/dev/null)"
    else
        new_val="$(grep 'enableExperiments' "$settings_path" | grep -o 'false\|true')"
    fi

    assert_eq "experiments set to false after remediation" "false" "$new_val"

    teardown_mock_home
}

test_remediate_shell_history() {
    echo -e "\n${YELLOW}▸ remediation — shell history secrets removed${RESET}"
    setup_mock_home
    create_shell_history_with_secrets

    local hist="${HOME}/.zsh_history"
    local lines_before
    lines_before="$(wc -l < "$hist" | tr -d ' ')"

    remediate_shell_history "$hist" > /dev/null 2>&1

    # Verify secrets are gone
    local secret_lines_after
    secret_lines_after="$(grep -cE '(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36})' "$hist" 2>/dev/null)" || secret_lines_after="0"

    assert_eq "no secret patterns remain in history" "0" "$secret_lines_after"

    # Verify non-secret lines survived
    local has_git_push
    grep -q "git push" "$hist" && has_git_push="yes" || has_git_push="no"
    assert_eq "non-secret lines preserved" "yes" "$has_git_push"

    # Verify backup was created
    local backup_found=false
    for f in "${HOME}"/.zsh_history.snoop.bak.*; do
        [[ -f "$f" ]] && backup_found=true && break
    done
    assert_eq "history backup created" "true" "$backup_found"

    teardown_mock_home
}

test_remediate_npm_telemetry() {
    echo -e "\n${YELLOW}▸ remediation — npm update-notifier disabled${RESET}"
    setup_mock_home
    create_npmrc_telemetry_on

    remediate_npm_telemetry "" > /dev/null 2>&1

    local has_notifier_off
    grep -q "update-notifier=false" "${HOME}/.npmrc" && has_notifier_off="yes" || has_notifier_off="no"

    assert_eq "update-notifier=false added to .npmrc" "yes" "$has_notifier_off"

    # Original registry line should still be there
    local has_registry
    grep -q "registry=" "${HOME}/.npmrc" && has_registry="yes" || has_registry="no"
    assert_eq "existing npmrc content preserved" "yes" "$has_registry"

    teardown_mock_home
}

test_remediate_idempotent() {
    echo -e "\n${YELLOW}▸ remediation — applying fix twice is idempotent${RESET}"
    setup_mock_home
    create_vscode_settings_telemetry_on

    local settings_path
    settings_path="$(get_vscode_settings_path "code")"

    # Apply twice
    remediate_vscode_telemetry_level "$settings_path" > /dev/null 2>&1
    remediate_vscode_telemetry_level "$settings_path" > /dev/null 2>&1

    local new_level
    new_level="$(json_get_nested "$settings_path" "telemetry.telemetryLevel")"

    assert_eq "telemetry still off after double apply" "off" "$new_level"

    # File should still be valid JSON (if jq available)
    if has_command jq; then
        jq . "$settings_path" > /dev/null 2>&1 && local valid="yes" || local valid="no"
        assert_eq "file still valid JSON after double apply" "yes" "$valid"
    fi

    teardown_mock_home
}

# ── Integration ───────────────────────────────────────────────────────────────

test_multiple_findings_same_category() {
    echo -e "\n${YELLOW}▸ multiple findings — same category accumulates${RESET}"
    setup_mock_home
    create_vscode_settings_telemetry_on
    create_shell_history_with_secrets
    create_aws_credentials
    create_dotenv_with_secrets "${HOME}/projects/app"
    SCAN_PATH="${HOME}"

    run_editor_checks
    run_secrets_checks

    local editor_count=0
    local secrets_count=0
    for finding in "${FINDINGS[@]}"; do
        local cat
        cat="$(echo "$finding" | cut -d'|' -f2)"
        case "$cat" in
            editor) editor_count=$((editor_count + 1)) ;;
            secrets) secrets_count=$((secrets_count + 1)) ;;
        esac
    done

    local editor_ok="no"
    local secrets_ok="no"
    [[ $editor_count -ge 1 ]] && editor_ok="yes"
    [[ $secrets_count -ge 2 ]] && secrets_ok="yes"

    assert_eq "at least 1 editor finding" "yes" "$editor_ok"
    assert_eq "at least 2 secrets findings" "yes" "$secrets_ok"

    teardown_mock_home
}

test_full_scan_clean_environment() {
    echo -e "\n${YELLOW}▸ integration — full scan on clean mock home${RESET}"
    setup_mock_home
    SCAN_PATH="${HOME}"

    # Run all check categories
    run_editor_checks
    run_git_checks
    run_secrets_checks
    run_apps_checks
    run_deps_checks

    # A totally empty mock home should produce very few findings
    # (no config files to flag, no secrets to find)
    local critical_count=0
    for finding in "${FINDINGS[@]}"; do
        local sev="${finding%%|*}"
        [[ "$sev" == "CRITICAL" ]] && critical_count=$((critical_count + 1))
    done

    assert_eq "clean home has no CRITICAL findings" "0" "$critical_count"

    teardown_mock_home
}

test_cli_version_flag() {
    echo -e "\n${YELLOW}▸ CLI — --version outputs version string${RESET}"

    local version_out
    version_out="$("${SNOOP_DIR}/snoop.sh" --version 2>&1)"

    assert_contains "version output contains snoop" "snoop" "$version_out"
    assert_contains "version output contains v" "v0." "$version_out"
}

test_cli_help_flag() {
    echo -e "\n${YELLOW}▸ CLI — --help exits 0 and shows usage${RESET}"

    local help_out
    help_out="$("${SNOOP_DIR}/snoop.sh" --help 2>&1)" && local help_exit=0 || local help_exit=$?

    assert_eq "--help exits 0" "0" "$help_exit"
    assert_contains "help shows usage" "Usage" "$help_out"
    assert_contains "help lists categories" "editor" "$help_out"
}

test_cli_invalid_arg() {
    echo -e "\n${YELLOW}▸ CLI — invalid argument exits 2${RESET}"

    "${SNOOP_DIR}/snoop.sh" --bogus-flag > /dev/null 2>&1
    local exit_code=$?

    assert_eq "invalid arg exits 2" "2" "$exit_code"
}

# ── Utility Functions ─────────────────────────────────────────────────────────

test_severity_color() {
    echo -e "\n${YELLOW}▸ utils — severity_color returns color codes${RESET}"

    local crit_color high_color info_color
    crit_color="$(severity_color "CRITICAL")"
    high_color="$(severity_color "HIGH")"
    info_color="$(severity_color "INFO")"

    # Just verify they're non-empty and different
    local crit_nonempty="no" different="no"
    [[ -n "$crit_color" ]] && crit_nonempty="yes"
    [[ "$crit_color" != "$info_color" ]] && different="yes"

    assert_eq "CRITICAL color is non-empty" "yes" "$crit_nonempty"
    assert_eq "CRITICAL and INFO have different colors" "yes" "$different"
}

test_get_vscode_settings_path() {
    echo -e "\n${YELLOW}▸ utils — get_vscode_settings_path returns correct paths${RESET}"

    local code_path codium_path cursor_path
    code_path="$(get_vscode_settings_path "code")"
    codium_path="$(get_vscode_settings_path "codium")"
    cursor_path="$(get_vscode_settings_path "cursor")"

    assert_contains "code path contains Code" "Code" "$code_path"
    assert_contains "codium path contains VSCodium" "VSCodium" "$codium_path"
    assert_contains "cursor path contains Cursor" "Cursor" "$cursor_path"

    # All should end in settings.json
    assert_contains "code path ends with settings.json" "settings.json" "$code_path"
}

# ─── Run All Tests ─────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  snoop test suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Source snoop libs once
source_snoop_libs

# Core plumbing
test_add_finding_format
test_add_finding_optional_fields
test_should_run_category_defaults
test_should_run_category_only
test_should_run_category_skip

# Check detection — positive cases (should find issues)
test_editor_check_telemetry_on
test_editor_check_cursor_telemetry
test_secrets_dotenv_with_keys
test_secrets_shell_history
test_secrets_aws_credentials
test_secrets_ssh_key
test_secrets_netrc
test_git_credential_plaintext
test_git_config_includes

# Check detection — negative cases (should NOT find issues)
test_editor_check_telemetry_off
test_editor_no_settings_file
test_secrets_dotenv_no_secrets
test_secrets_shell_history_clean
test_git_credential_encrypted
test_secrets_scan_path_scoping

# Output
test_json_output_valid
test_json_output_empty
test_text_report_output

# Exit codes
test_exit_code_with_critical
test_exit_code_with_high
test_exit_code_clean
test_exit_code_no_findings

# Remediation safety
test_backup_creation
test_backup_nonexistent_file
test_remediate_vscode_telemetry
test_remediate_vscode_experiments
test_remediate_shell_history
test_remediate_npm_telemetry
test_remediate_idempotent

# Utility functions
test_severity_color
test_get_vscode_settings_path

# CLI argument handling
test_cli_version_flag
test_cli_help_flag
test_cli_invalid_arg

# Integration
test_multiple_findings_same_category
test_full_scan_clean_environment

# ─── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "  ${GREEN}All ${TESTS_PASSED}/${TESTS_RUN} tests passed${RESET}"
else
    echo -e "  ${RED}${TESTS_FAILED}/${TESTS_RUN} tests failed${RESET}"
    echo ""
    for msg in "${FAIL_MESSAGES[@]}"; do
        echo -e "  ${RED}✗${RESET} ${msg}"
    done
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1

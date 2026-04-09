#!/usr/bin/env bash
# snoop — Dependency manager checks

run_deps_checks() {
    _check_npm_registry
    _check_pip_index
}

_check_npm_registry() {
    has_command npm || return

    local registry
    registry="$(npm config get registry 2>/dev/null || echo "")"

    if [[ -n "$registry" ]]; then
        add_finding "INFO" "deps" \
            "npm registry" \
            "${HOME}/.npmrc" \
            "registry = ${registry}" \
            "All package installs and metadata lookups go through this registry." \
            "" \
            "" \
            ""
    fi
}

_check_pip_index() {
    has_command pip3 || has_command pip || return

    local pip_cmd="pip3"
    has_command pip3 || pip_cmd="pip"

    local index_url
    index_url="$($pip_cmd config get global.index-url 2>/dev/null || echo "https://pypi.org/simple (default)")"

    add_finding "INFO" "deps" \
        "pip index URL" \
        "${HOME}/.config/pip/pip.conf" \
        "index-url = ${index_url}" \
        "All Python package installs go through this index." \
        "" \
        "" \
        ""
}

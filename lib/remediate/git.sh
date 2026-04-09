#!/usr/bin/env bash
# snoop — Git remediation functions

remediate_git_credential_helper() {
    local _file="$1"  # unused, we operate on git config

    if is_macos; then
        git config --global credential.helper osxkeychain
        echo "Set credential.helper = osxkeychain"
    elif is_linux; then
        if has_command git-credential-libsecret; then
            git config --global credential.helper libsecret
            echo "Set credential.helper = libsecret"
        else
            echo "libsecret credential helper not found. Install it with:"
            echo "  sudo apt install libsecret-1-0 libsecret-1-dev"
            echo "  sudo make -C /usr/share/doc/git/contrib/credential/libsecret"
            return 1
        fi
    fi
}

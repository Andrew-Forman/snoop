#!/usr/bin/env bash
# snoop — System remediation functions

# System remediations are mostly manual (require sudo, system preferences, or recovery mode).
# This file provides guided instructions rather than automatic fixes.

remediate_enable_firewall() {
    local _file="$1"

    if is_macos; then
        echo "Enabling macOS firewall..."
        sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
        echo "Firewall enabled."
    elif is_linux; then
        if has_command ufw; then
            echo "Enabling UFW firewall..."
            sudo ufw --force enable
            echo "UFW firewall enabled."
        fi
    fi
}

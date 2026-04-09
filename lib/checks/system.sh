#!/usr/bin/env bash
# snoop — System & disk security checks

run_system_checks() {
    _check_disk_encryption
    _check_firewall
    _check_screen_lock
    if is_macos; then
        _check_gatekeeper
        _check_sip
    fi
}

_check_disk_encryption() {
    if is_macos; then
        local fv_status
        fv_status="$(fdesetup status 2>/dev/null || echo "unknown")"

        if ! echo "$fv_status" | grep -q "FileVault is On"; then
            add_finding "CRITICAL" "system" \
                "Disk encryption (FileVault) is disabled" \
                "" \
                "$fv_status" \
                "Without full-disk encryption, anyone with physical access to your machine (theft, border search, repair shop) can read all files including source code, credentials, and keys." \
                "Enable FileVault: System Preferences → Security & Privacy → FileVault → Turn On" \
                "Initial encryption takes a few hours (background). Slight CPU overhead (negligible on modern Macs with T2/M-series)." \
                ""
        fi
    elif is_linux; then
        if has_command lsblk; then
            local encrypted
            encrypted="$(lsblk -o TYPE 2>/dev/null | grep -c crypt || echo 0)"
            if [[ "$encrypted" -eq 0 ]]; then
                add_finding "CRITICAL" "system" \
                    "No LUKS disk encryption detected" \
                    "" \
                    "No encrypted partitions found" \
                    "Without full-disk encryption, anyone with physical access to your machine can read all files." \
                    "Set up LUKS encryption (typically done during OS install)" \
                    "Requires reinstall or complex migration. Best done during initial setup." \
                    ""
            fi
        fi
    fi
}

_check_firewall() {
    if is_macos; then
        local fw_status
        # Try the modern socketfilterfw approach
        fw_status="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || echo "unknown")"

        if ! echo "$fw_status" | grep -qi "enabled"; then
            add_finding "MEDIUM" "system" \
                "macOS firewall is disabled" \
                "" \
                "$fw_status" \
                "Without the firewall enabled, all incoming connections to your machine are allowed. This increases exposure if you're on a public/shared network." \
                "System Settings → Network → Firewall → toggle on. Or: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on" \
                "When a local server listens on a port, macOS will pop a one-time prompt to allow it." \
                ""
        fi
    elif is_linux; then
        if has_command ufw; then
            local ufw_status
            ufw_status="$(sudo ufw status 2>/dev/null || ufw status 2>/dev/null || echo "unknown")"
            if echo "$ufw_status" | grep -qi "inactive"; then
                add_finding "MEDIUM" "system" \
                    "UFW firewall is inactive" \
                    "" \
                    "ufw status: inactive" \
                    "Without a firewall, all incoming connections are allowed." \
                    "Enable with: sudo ufw enable" \
                    "May block incoming connections to dev servers. Add rules as needed." \
                    ""
            fi
        fi
    fi
}

_check_screen_lock() {
    if is_macos; then
        # Check screen saver idle time
        local idle_time
        idle_time="$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null || echo "")"

        if [[ -z "$idle_time" || "$idle_time" -gt 300 || "$idle_time" -eq 0 ]]; then
            add_finding "LOW" "system" \
                "Screen lock timeout is too long or disabled" \
                "" \
                "idleTime = ${idle_time:-not set} seconds" \
                "A long screen lock delay (or no auto-lock) means your machine is accessible to anyone nearby when you step away." \
                "Set screen lock to 5 minutes or less: System Preferences → Lock Screen" \
                "You'll need to unlock more frequently." \
                ""
        fi
    fi
}

_check_gatekeeper() {
    local gk_status
    gk_status="$(spctl --status 2>/dev/null || echo "unknown")"

    if ! echo "$gk_status" | grep -q "assessments enabled"; then
        add_finding "MEDIUM" "system" \
            "macOS Gatekeeper is disabled" \
            "" \
            "$gk_status" \
            "Gatekeeper checks that applications are signed and notarized by Apple. Disabling it allows unsigned/unnotarized apps to run, increasing malware risk." \
            "Re-enable with: sudo spctl --master-enable" \
            "You may need to individually approve unsigned apps you trust." \
            ""
    fi
}

_check_sip() {
    local sip_status
    sip_status="$(csrutil status 2>/dev/null || echo "unknown")"

    if ! echo "$sip_status" | grep -q "enabled"; then
        add_finding "MEDIUM" "system" \
            "System Integrity Protection (SIP) is disabled" \
            "" \
            "$sip_status" \
            "SIP protects system files and processes from modification. Disabling it exposes your system to rootkits and persistent malware." \
            "Re-enable by booting to Recovery Mode and running: csrutil enable" \
            "Some developer tools (certain kernel extensions, dtrace uses) require SIP disabled. Re-enabling may break them." \
            ""
    fi
}

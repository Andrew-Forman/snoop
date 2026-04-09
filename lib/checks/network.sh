#!/usr/bin/env bash
# snoop — DNS & network checks

run_network_checks() {
    _check_dns_resolver
    _check_vpn
}

_check_dns_resolver() {
    local dns_servers=""

    if is_macos; then
        dns_servers="$(scutil --dns 2>/dev/null | grep 'nameserver\[' | head -5 | awk '{print $3}' | sort -u | tr '\n' ', ' | sed 's/,$//')"
    elif is_linux; then
        if [[ -f /etc/resolv.conf ]]; then
            dns_servers="$(grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | tr '\n' ', ' | sed 's/,$//')"
        fi
    fi

    [[ -z "$dns_servers" ]] && return

    # Check for common ISP/default DNS (not encrypted resolvers)
    local known_private=("1.1.1.1" "1.0.0.1" "9.9.9.9" "149.112.112.112" "8.8.8.8" "8.8.4.4" "208.67.222.222" "208.67.220.220")
    local is_known=false

    for dns in $(echo "$dns_servers" | tr ',' ' '); do
        for known in "${known_private[@]}"; do
            if [[ "$dns" == "$known" ]]; then
                is_known=true
                break
            fi
        done
    done

    if [[ "$is_known" == false ]]; then
        add_finding "LOW" "network" \
            "DNS resolver may be ISP default" \
            "/etc/resolv.conf" \
            "DNS servers: ${dns_servers}" \
            "ISP DNS servers can log your queries, enabling tracking of which services and sites you access. They may also inject ads or block domains." \
            "Switch to an encrypted resolver: Quad9 (9.9.9.9), Cloudflare (1.1.1.1), or configure DNS-over-HTTPS" \
            "Encrypted DNS may be slightly slower for initial resolution. Some corporate networks require their DNS servers." \
            ""
    fi
}

_check_vpn() {
    local vpn_active=false
    local vpn_name=""

    if is_macos; then
        # Check for active VPN interfaces
        local utun_count
        utun_count="$(ifconfig 2>/dev/null | grep -c 'utun' || echo 0)"
        if [[ "$utun_count" -gt 1 ]]; then
            vpn_active=true
            vpn_name="utun interface detected"
        fi

        # Check for WireGuard
        if pgrep -x "wireguard-go" &>/dev/null || pgrep -x "WireGuard" &>/dev/null; then
            vpn_active=true
            vpn_name="WireGuard"
        fi
    elif is_linux; then
        if ip link show type wireguard &>/dev/null 2>&1; then
            vpn_active=true
            vpn_name="WireGuard"
        elif ip tuntap show 2>/dev/null | grep -q tun; then
            vpn_active=true
            vpn_name="TUN device detected"
        fi
    fi

    add_finding "INFO" "network" \
        "VPN status" \
        "" \
        "$(if [[ "$vpn_active" == true ]]; then echo "Active: ${vpn_name}"; else echo "No VPN detected"; fi)" \
        "A VPN encrypts your network traffic and masks your IP. Useful on untrusted networks." \
        "" \
        "" \
        ""
}

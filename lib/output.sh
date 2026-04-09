#!/usr/bin/env bash
# snoop — Report output formatting

output_report() {
    local critical=0 high=0 medium=0 low=0 info=0 fixable=0 manual=0

    for finding in "${FINDINGS[@]}"; do
        IFS='|' read -r sev category title file current risk fix_desc tradeoff fix_func <<< "$finding"
        case "$sev" in
            CRITICAL) critical=$((critical + 1)) ;;
            HIGH)     high=$((high + 1)) ;;
            MEDIUM)   medium=$((medium + 1)) ;;
            LOW)      low=$((low + 1)) ;;
            INFO)     info=$((info + 1)) ;;
        esac
        if [[ -n "$fix_func" ]]; then
            fixable=$((fixable + 1))
        else
            manual=$((manual + 1))
        fi
    done

    local total=${#FINDINGS[@]}

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║           snoop — Privacy Audit              ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════╣${NC}"

    _print_bar "CRITICAL" "$critical" "$total"
    _print_bar "HIGH" "$high" "$total"
    _print_bar "MEDIUM" "$medium" "$total"
    _print_bar "LOW" "$low" "$total"
    _print_bar "INFO" "$info" "$total"

    echo -e "${BOLD}║                                              ║${NC}"
    printf "${BOLD}║${NC}  Overall: %-34s ${BOLD}║${NC}\n" "${total} findings across scan"
    printf "${BOLD}║${NC}  Fixable automatically: %-21s ${BOLD}║${NC}\n" "$fixable"
    printf "${BOLD}║${NC}  Requires manual action: %-20s ${BOLD}║${NC}\n" "$manual"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    # Per-finding details
    if [[ $total -gt 0 ]]; then
        echo -e "${BOLD}─── Findings ───────────────────────────────────────${NC}"
        echo ""

        # Sort by severity
        local sorted_findings=()
        for sev_level in CRITICAL HIGH MEDIUM LOW INFO; do
            for finding in "${FINDINGS[@]}"; do
                local fsev="${finding%%|*}"
                if [[ "$fsev" == "$sev_level" ]]; then
                    sorted_findings+=("$finding")
                fi
            done
        done

        for finding in "${sorted_findings[@]}"; do
            IFS='|' read -r sev category title file current risk fix_desc tradeoff fix_func <<< "$finding"
            local color
            color="$(severity_color "$sev")"

            echo -e "${color}[${sev}]${NC} ${BOLD}${title}${NC}"
            [[ -n "$file" ]]     && echo -e "  ${DIM}File:${NC} ${file}"
            [[ -n "$current" ]]  && echo -e "  ${DIM}Current:${NC} ${current}"
            [[ -n "$risk" ]]     && echo -e "  ${DIM}Risk:${NC} ${risk}"
            [[ -n "$fix_desc" ]] && echo -e "  ${DIM}Fix:${NC} ${fix_desc}"
            [[ -n "$tradeoff" ]] && echo -e "  ${DIM}Trade-off:${NC} ${tradeoff}"
            echo ""
        done
    else
        echo ""
        echo -e "${GREEN}${BOLD}No findings. Your environment looks clean.${NC}"
        echo ""
    fi
}

_print_bar() {
    local label="$1"
    local count="$2"
    local total="$3"
    local color
    color="$(severity_color "$label")"

    local bar_len=10
    local filled=0
    if [[ $total -gt 0 && $count -gt 0 ]]; then
        filled=$(( (count * bar_len + total - 1) / total ))
        [[ $filled -lt 1 ]] && filled=1
        [[ $filled -gt $bar_len ]] && filled=$bar_len
    fi
    local empty=$((bar_len - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    local count_str
    if [[ $count -eq 1 ]]; then
        count_str="${count} finding"
    else
        count_str="${count} findings"
    fi

    printf "${BOLD}║${NC}  ${color}%-9s${NC} ${bar}  %-16s ${BOLD}║${NC}\n" "$label" "$count_str"
}

output_json() {
    echo "["
    local first=true
    for finding in "${FINDINGS[@]}"; do
        IFS='|' read -r sev category title file current risk fix_desc tradeoff fix_func <<< "$finding"

        if [[ "$first" == true ]]; then
            first=false
        else
            echo ","
        fi

        # Escape double quotes in values
        title="${title//\"/\\\"}"
        file="${file//\"/\\\"}"
        current="${current//\"/\\\"}"
        risk="${risk//\"/\\\"}"
        fix_desc="${fix_desc//\"/\\\"}"
        tradeoff="${tradeoff//\"/\\\"}"

        cat <<JSONENTRY
  {
    "severity": "${sev}",
    "category": "${category}",
    "title": "${title}",
    "file": "${file}",
    "current": "${current}",
    "risk": "${risk}",
    "fix": "${fix_desc}",
    "tradeoff": "${tradeoff}",
    "auto_fixable": $([ -n "$fix_func" ] && echo "true" || echo "false")
  }
JSONENTRY
    done
    echo ""
    echo "]"
}

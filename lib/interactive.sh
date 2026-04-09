#!/usr/bin/env bash
# snoop — Interactive remediation mode

run_interactive() {
    local fixable_findings=()

    # Collect fixable findings sorted by severity (CRITICAL → HIGH → MEDIUM → LOW → INFO)
    for sev_level in CRITICAL HIGH MEDIUM LOW INFO; do
        for finding in "${FINDINGS[@]}"; do
            IFS='|' read -r sev category title file current risk fix_desc tradeoff fix_func <<< "$finding"
            if [[ -n "$fix_func" && "$sev" == "$sev_level" ]]; then
                fixable_findings+=("$finding")
            fi
        done
    done

    if [[ ${#fixable_findings[@]} -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}No auto-fixable findings. Nothing to remediate interactively.${NC}"
        return
    fi

    echo ""
    echo -e "${BOLD}─── Interactive Remediation ─────────────────────────${NC}"
    echo -e "${DIM}Walking through ${#fixable_findings[@]} fixable findings.${NC}"
    echo ""

    local applied=0
    local skipped=0

    for finding in "${fixable_findings[@]}"; do
        IFS='|' read -r sev category title file current risk fix_desc tradeoff fix_func <<< "$finding"
        local color
        color="$(severity_color "$sev")"

        echo -e "${color}[${sev}]${NC} ${BOLD}${title}${NC}"
        echo -e "  ${DIM}Risk:${NC} ${risk}"
        echo -e "  ${DIM}Fix:${NC} ${fix_desc}"
        echo -e "  ${DIM}Trade-off:${NC} ${tradeoff}"
        echo ""

        while true; do
            echo -ne "  ${BOLD}[A]${NC}pply fix  ${BOLD}[S]${NC}kip  ${BOLD}[D]${NC}etails  ${BOLD}[Q]${NC}uit → "
            read -r -n 1 choice
            echo ""

            case "${choice,,}" in
                a)
                    echo ""
                    if $fix_func "$file" 2>&1 | sed 's/^/  /'; then
                        echo -e "  ${GREEN}✓ Fix applied.${NC}"
                        applied=$((applied + 1))
                    else
                        echo -e "  ${RED}✗ Fix failed. No changes made.${NC}"
                    fi
                    echo ""
                    break
                    ;;
                s)
                    echo -e "  ${DIM}Skipped.${NC}"
                    skipped=$((skipped + 1))
                    echo ""
                    break
                    ;;
                d)
                    echo ""
                    [[ -n "$file" ]]    && echo -e "  ${DIM}File:${NC} ${file}"
                    [[ -n "$current" ]] && echo -e "  ${DIM}Current value:${NC} ${current}"
                    echo ""
                    ;;
                q)
                    echo ""
                    echo -e "${BOLD}Exiting. Applied ${applied} fixes, skipped ${skipped}.${NC}"
                    return
                    ;;
                *)
                    echo -e "  ${DIM}Invalid choice. Use A, S, D, or Q.${NC}"
                    ;;
            esac
        done
    done

    echo -e "${BOLD}Done. Applied ${applied} fixes, skipped ${skipped}.${NC}"
}

#!/usr/bin/env bash
# snoop — Secrets remediation functions

remediate_shell_history() {
    local hist_file="$1"
    [[ -z "$hist_file" || ! -f "$hist_file" ]] && return 1

    backup_file "$hist_file"

    # Remove lines matching common secret patterns
    local patterns='(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[A-Z0-9]{16}|xox[baprs]-[a-zA-Z0-9-]{10,}|glpat-[a-zA-Z0-9_-]{20,}|-----BEGIN)'
    local count_before
    count_before="$(wc -l < "$hist_file" | tr -d ' ')"

    grep -vE "$patterns" "$hist_file" > "${hist_file}.clean" && mv "${hist_file}.clean" "$hist_file"

    local count_after
    count_after="$(wc -l < "$hist_file" | tr -d ' ')"
    local removed=$((count_before - count_after))

    echo "Removed ${removed} lines containing potential secrets from ${hist_file}"

    # Suggest HISTIGNORE
    if [[ "$hist_file" == *"zsh"* ]]; then
        echo "Tip: Add to ~/.zshrc to prevent future leaks:"
        echo '  setopt HIST_IGNORE_SPACE  # prefix sensitive commands with a space'
    elif [[ "$hist_file" == *"bash"* ]]; then
        echo "Tip: Add to ~/.bashrc to prevent future leaks:"
        echo '  HISTCONTROL=ignorespace  # prefix sensitive commands with a space'
    fi
}

#!/usr/bin/env bash
# snoop installer — downloads and sets up snoop locally
set -euo pipefail

INSTALL_DIR="${HOME}/.snoop"
REPO_URL="https://github.com/<org>/snoop"

echo "Installing snoop..."

if [[ -d "$INSTALL_DIR" ]]; then
    echo "Updating existing installation..."
    cd "$INSTALL_DIR" && git pull --quiet
else
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "${INSTALL_DIR}/snoop.sh"

# Add to PATH if not already there
SHELL_RC=""
if [[ -f "${HOME}/.zshrc" ]]; then
    SHELL_RC="${HOME}/.zshrc"
elif [[ -f "${HOME}/.bashrc" ]]; then
    SHELL_RC="${HOME}/.bashrc"
fi

if [[ -n "$SHELL_RC" ]]; then
    if ! grep -q 'snoop' "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo '# snoop — Dev Environment Privacy Audit' >> "$SHELL_RC"
        echo "export PATH=\"\${HOME}/.snoop:\${PATH}\"" >> "$SHELL_RC"
        echo "alias snoop='snoop.sh'" >> "$SHELL_RC"
        echo "Added snoop to PATH in ${SHELL_RC}"
    fi
fi

echo ""
echo "snoop installed to ${INSTALL_DIR}"
echo "Run 'snoop' or '${INSTALL_DIR}/snoop.sh' to start an audit."
echo ""

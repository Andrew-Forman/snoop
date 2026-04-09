# snoop

A single shell script that audits your dev environment for privacy and IP leakage risks. It scans your machine for telemetry, plaintext secrets, insecure configs, and data exfiltration vectors across your entire dev toolchain — then walks you through fixing them.

No dependencies. Pure bash. Zero telemetry.

## Why

Developers working on proprietary code routinely use tools that silently transmit telemetry, code snippets, file metadata, and usage patterns to third parties. There is no simple way to audit your local environment for these leakage vectors and fix them in a controlled way.

snoop gives you a clear picture of what's leaking, to whom, and what you can do about it.

## Install

Clone and run:

```bash
git clone https://github.com/Andrew-Forman/snoop.git
cd snoop
chmod +x snoop.sh
./snoop.sh
```

Or one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/snoop/main/install.sh | bash
```

No package manager, no build step, no runtime dependencies.

## Usage

### Report mode (default)

```bash
./snoop.sh
```

Runs all checks and prints a structured report. No interactive prompts, no file modifications. Safe to pipe or run in CI.

```
╔══════════════════════════════════════════════╗
║           snoop — Privacy Audit              ║
╠══════════════════════════════════════════════╣
║  CRITICAL  █░░░░░░░░░  1 finding        ║
║  HIGH      ██░░░░░░░░  2 findings       ║
║  MEDIUM    ██░░░░░░░░  3 findings       ║
║  LOW       █████░░░░░  8 findings       ║
║  INFO      ███░░░░░░░  4 findings       ║
║                                              ║
║  Overall: 18 findings across scan            ║
║  Fixable automatically: 6                     ║
║  Requires manual action: 12                   ║
╚══════════════════════════════════════════════╝

─── Findings ───────────────────────────────────────

[CRITICAL] Plaintext .env files with secrets found
  File: Multiple locations
  Current:   ~/projects/myapp/.env (3 potential secrets)

[HIGH] VS Code extensions with known telemetry installed
  Current: Installed: GitHub.copilot, GitHub.copilot-chat, ms-python.python
  Risk: These extensions are known to send usage data, code snippets, or
        file metadata to their vendors.
  Fix: Review each extension and disable/remove those not needed.
  Trade-off: Removing Copilot means losing AI code completion.

[HIGH] AWS credentials stored in plaintext
  File: ~/.aws/credentials
  Current: Plaintext access keys found
  Risk: Static AWS credentials can be exfiltrated by malware or exposed
        in backups. They often have broad permissions.
  Fix: Switch to AWS SSO or environment-based auth with short-lived tokens

[MEDIUM] SSH private key without passphrase
  File: ~/.ssh/id_ed25519
  Current: No passphrase set
  Risk: If this key is stolen, it can be used immediately without any
        additional authentication.
  Fix: Add a passphrase with: ssh-keygen -p -f ~/.ssh/id_ed25519

[MEDIUM] macOS firewall is disabled
  Current: Firewall is disabled. (State = 0)
  Fix: System Settings → Network → Firewall → toggle on.
       Or: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

[LOW] VS Code A/B experiments enabled
  File: ~/Library/Application Support/Code/User/settings.json
  Fix: Set workbench.enableExperiments to false
  ...
```

Each finding includes what was found, the risk in plain English, the recommended fix, and the trade-off so you can make an informed decision.

### Interactive mode

```bash
./snoop.sh --interactive
```

Runs the full scan, then walks you through each fixable finding one at a time. Findings are sorted by severity — CRITICAL and HIGH first.

```
[HIGH] VS Code telemetry is enabled
  Risk: VS Code sends usage data, error reports, and extension usage
        patterns to Microsoft.
  Fix: Set telemetry.telemetryLevel to "off"
  Trade-off: You lose automatic crash reporting. No impact on core
             editor functionality.

  [A]pply fix  [S]kip  [D]etails  [Q]uit →
```

- **Apply** — backs up the original file, applies the fix, confirms success
- **Skip** — moves to the next finding
- **Details** — shows file paths and current values
- **Quit** — exits immediately, no further changes

Every file modification creates a `.snoop.bak.<timestamp>` backup in the same directory. All fixes are reversible.

### Scan specific categories

```bash
./snoop.sh --only editor,secrets    # only these categories
./snoop.sh --skip network,deps      # everything except these
```

### JSON output

```bash
./snoop.sh --format json
```

Machine-readable output for integration with other tools.

### Custom scan path

```bash
./snoop.sh --scan-path ~/projects
```

By default snoop scans `~/` and common dev directories. Use `--scan-path` to target a specific directory.

### All options

```
./snoop.sh [options]

--interactive          Walk through each finding and optionally apply fixes
--only <categories>    Only run specific categories (comma-separated)
--skip <categories>    Skip specific categories (comma-separated)
--format <text|json>   Output format (default: text)
--scan-path <path>     Custom path to scan for secrets/repos (default: ~/)
--version              Show version
--help                 Show this help
```

## What it checks

| Category | What it looks for |
|----------|-------------------|
| **editor** | VS Code, Cursor, VSCodium, JetBrains telemetry settings. Extensions with known telemetry (Copilot, etc). |
| **git** | Plaintext credential helpers, gitconfig includes, GitHub CLI token scopes. |
| **secrets** | `.env` files with API keys, shell history with leaked tokens, SSH keys without passphrases, AWS credentials, `.netrc`. |
| **system** | Disk encryption (FileVault/LUKS), firewall status, screen lock timeout, Gatekeeper, SIP. |
| **apps** | Homebrew analytics, npm update notifier, Docker Desktop telemetry. |
| **network** | DNS resolver (ISP default vs encrypted), VPN status. |
| **deps** | npm/pip registry configuration, lockfile presence. |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | No CRITICAL or HIGH findings |
| 1 | CRITICAL or HIGH findings present |
| 2 | Invalid arguments |

## Architecture

```
snoop/
├── snoop.sh                  # Entry point, argument parsing, orchestration
├── lib/
│   ├── utils.sh              # OS detection, JSON helpers, backup, colors
│   ├── output.sh             # Report formatting (text and JSON)
│   ├── interactive.sh        # Interactive remediation UI
│   ├── checks/
│   │   ├── editor.sh         # Editor & IDE telemetry checks
│   │   ├── git.sh            # Git & VCS checks
│   │   ├── secrets.sh        # Secrets & credentials checks
│   │   ├── system.sh         # System & disk security checks
│   │   ├── apps.sh           # Application telemetry checks
│   │   ├── network.sh        # DNS & network checks
│   │   └── deps.sh           # Dependency manager checks
│   └── remediate/
│       ├── editor.sh         # Editor fix functions
│       ├── git.sh            # Git fix functions
│       ├── secrets.sh        # Secrets fix functions
│       ├── system.sh         # System fix functions
│       └── apps.sh           # App telemetry fix functions
├── tests/
│   └── run_tests.sh          # Test suite (78 tests)
├── install.sh
├── LICENSE                    # MIT
└── README.md
```

Each check category is a self-contained module. Checks register findings via `add_finding`. Remediations are separate functions that back up before writing.

## Contributing

### Adding a new check

1. Add your check function to the appropriate file in `lib/checks/` (or create a new category).
2. Register findings with `add_finding`:

```bash
add_finding "SEVERITY" "category" \
    "Short title" \
    "/path/to/file" \
    "Current value or state" \
    "What's the risk, in plain English" \
    "What the fix does" \
    "What you lose by applying it" \
    "fix_function_name"  # leave empty if manual-only
```

3. If auto-fixable, add the remediation function in `lib/remediate/`. It receives the file path as `$1`. Always call `backup_file` before modifying anything.
4. Add tests in `tests/run_tests.sh` — mock the config in a temp `$HOME`, run the check, assert findings.

### Design principles

- **Audit first, remediate second.** Default mode is read-only.
- **No dependencies.** Pure bash with standard Unix tools. Runs on a fresh machine.
- **Explain, don't just flag.** Every finding includes what's leaking, to whom, what the risk is, and what the fix does.
- **Non-destructive.** All remediations are reversible via `.snoop.bak` files.
- **No telemetry.** This tool has zero analytics, zero phone-home. It would be hypocritical otherwise.

### Running tests

```bash
./tests/run_tests.sh
```

Tests create a mock `$HOME` in a temp directory, set up config files, run checks, and assert findings. No real files are modified.

## Platform support

- **macOS** — primary target, fully supported
- **Linux** — supported with conditional branches
- **Windows/WSL** — not supported in v1

## License

MIT

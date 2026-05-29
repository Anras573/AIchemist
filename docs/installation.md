# Installation

## From Marketplace (Recommended)

**Claude Code:**
```bash
claude plugin install aichemist
```

**GitHub Copilot CLI:**
```bash
copilot plugin install aichemist
```

## From Local Path

1. Clone the repository:

   ```bash
   git clone https://github.com/Anras573/AIchemist.git
   ```

2. Install the plugin:

   **Claude Code:**
   ```bash
   claude plugin install ./AIchemist
   ```

   **GitHub Copilot CLI:**
   ```bash
   copilot plugin install ./AIchemist
   ```

You can specify the installation scope with `--scope user`, `--scope project`, or `--scope local`.

## Machine Bootstrap (Personal Setup)

For a full macOS machine bootstrap (dependencies + plugin install for both CLIs), run:

```bash
tools/bootstrap-machine.sh install
```

This installs the dependency set defined in `Brewfile`, installs tool-specific dependencies (Playwright CLI, Microsoft 365 CLI, MemPalace), pulls the Markitdown image, and installs AIchemist from the local repo path for both Claude Code and GitHub Copilot CLI.

To verify a machine state at any time:

```bash
tools/bootstrap-machine.sh doctor
```

`doctor` reports **READY/MISSING** with exact remediation commands.

## Post-Installation

The plugin works out of the box. User-specific configuration (like Atlassian account info) is auto-fetched on first use.

**(Optional)** Configure the MCP servers for additional capabilities. See [configuration.md](configuration.md) for details.

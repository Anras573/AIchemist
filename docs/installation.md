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

## Post-Installation

The plugin works out of the box. User-specific configuration (like Atlassian account info) is auto-fetched on first use.

**(Optional)** Configure the MCP servers for additional capabilities. See [configuration.md](configuration.md) for details.

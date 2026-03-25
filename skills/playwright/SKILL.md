---
name: Playwright
description: |
  Use this skill for browser automation, web testing, and UI interaction tasks. Prefer this over Playwright MCP — it uses the token-efficient playwright-cli instead of loading large MCP tool schemas and accessibility trees into context.
  Trigger phrases: "test this page", "automate the browser", "take a screenshot of", "check this UI", "fill out this form", "test the flow on", "click through", "scrape this page", "use playwright", "browser test", "open a browser", "navigate to".
---

# Playwright Skill

Browser automation and web testing using `playwright-cli` — a token-efficient alternative to Playwright MCP. CLI invocations avoid loading large tool schemas and verbose accessibility trees into the model context.

## Why CLI over MCP

| | playwright-cli (this skill) | Playwright MCP |
|---|---|---|
| Token cost | Low — concise CLI commands | High — full tool schemas + a11y trees in context |
| Best for | Coding agents, test automation, high-throughput workflows | Exploratory automation, persistent state, long-running loops |

## Prerequisites

```bash
npm install -g @playwright/cli@latest
playwright-cli --help  # verify installation
```

## Installation

This plugin ships the skill. No per-repo installation needed — the skill is available in all sessions where this plugin is loaded.

For local skill installation (optional, adds task-specific guides):

```bash
playwright-cli install --skills
```

## Sessions

playwright-cli keeps the browser in memory by default. Cookies and storage persist between CLI calls within a session, but are lost when the browser closes.

```bash
# Default session (in-memory)
playwright-cli open https://example.com

# Named session (useful for parallel automation or project isolation)
playwright-cli -s=myapp open https://example.com

# Persistent session (profile saved to disk across restarts)
playwright-cli open https://example.com --persistent

# Set default session via env var
PLAYWRIGHT_CLI_SESSION=myapp playwright-cli open https://example.com
```

Manage sessions:

```bash
playwright-cli list        # list all active sessions
playwright-cli close-all   # close all browsers
playwright-cli kill-all    # forcefully kill all browser processes
```

## Snapshots

After most commands, playwright-cli outputs a snapshot of the current page state. Use element refs (e.g. `e21`, `e35`) from snapshots for subsequent interactions.

```bash
playwright-cli snapshot              # capture snapshot on demand
playwright-cli snapshot --filename=f # save to specific file
```

## Command Reference

### Core Navigation

```bash
playwright-cli open [url]            # open browser, optionally navigate
playwright-cli goto <url>            # navigate to a url
playwright-cli go-back               # go back
playwright-cli go-forward            # go forward
playwright-cli reload                # reload the page
playwright-cli close                 # close the page
```

### Interaction

```bash
playwright-cli click <ref> [button]  # click an element (ref from snapshot)
playwright-cli dblclick <ref>        # double click
playwright-cli type <text>           # type into focused element
playwright-cli fill <ref> <text>     # fill an input field
playwright-cli hover <ref>           # hover over element
playwright-cli select <ref> <val>    # select dropdown option
playwright-cli check <ref>           # check checkbox/radio
playwright-cli uncheck <ref>         # uncheck checkbox/radio
playwright-cli drag <from> <to>      # drag and drop
playwright-cli press <key>           # press a key (e.g. Enter, ArrowLeft)
playwright-cli upload <file>         # upload a file
playwright-cli resize <w> <h>        # resize the browser window
```

### Dialogs

```bash
playwright-cli dialog-accept [text]  # accept a dialog (optional prompt text)
playwright-cli dialog-dismiss        # dismiss a dialog
```

### Tabs

```bash
playwright-cli tab-list              # list all open tabs
playwright-cli tab-new [url]         # open a new tab
playwright-cli tab-select <index>    # switch to tab
playwright-cli tab-close [index]     # close a tab (default: current)
```

### Capture

```bash
playwright-cli screenshot [ref]             # screenshot of page or element
playwright-cli screenshot --filename=f.png  # save with specific filename
playwright-cli pdf                          # save page as PDF
playwright-cli pdf --filename=page.pdf
```

### DevTools / Debugging

```bash
playwright-cli console [min-level]   # list console messages (error/warn/info/debug)
playwright-cli network               # list network requests since page load
playwright-cli eval <func> [ref]     # evaluate JavaScript on page or element
playwright-cli run-code <code>       # run a Playwright code snippet
playwright-cli tracing-start         # start trace recording
playwright-cli tracing-stop          # stop trace recording
playwright-cli video-start           # start video recording
playwright-cli video-stop [filename] # stop video recording
```

### Storage

```bash
# State
playwright-cli state-save [filename]   # save storage state
playwright-cli state-load <filename>   # load storage state

# Cookies
playwright-cli cookie-list [--domain]
playwright-cli cookie-get <name>
playwright-cli cookie-set <name> <val>
playwright-cli cookie-delete <name>
playwright-cli cookie-clear

# LocalStorage
playwright-cli localstorage-list
playwright-cli localstorage-get <key>
playwright-cli localstorage-set <k> <v>
playwright-cli localstorage-delete <k>
playwright-cli localstorage-clear

# SessionStorage
playwright-cli sessionstorage-list
playwright-cli sessionstorage-get <k>
playwright-cli sessionstorage-set <k> <v>
playwright-cli sessionstorage-delete <k>
playwright-cli sessionstorage-clear
```

### Network Mocking

```bash
playwright-cli route <pattern> [opts]  # mock network requests matching pattern
playwright-cli route-list              # list active routes
playwright-cli unroute [pattern]       # remove route(s)
```

## Typical Workflow

```bash
# 1. Open a page and take a snapshot to get element refs
playwright-cli open https://example.com
playwright-cli snapshot

# 2. Interact using refs from the snapshot
playwright-cli fill e12 "search term"
playwright-cli press Enter

# 3. Capture result
playwright-cli screenshot --filename=result.png
```

## Open Parameters

```bash
playwright-cli open --browser=chrome     # use specific browser (chromium/firefox/webkit)
playwright-cli open --headed             # show the browser window
playwright-cli open --persistent         # persist profile to disk
playwright-cli open --profile=<path>     # use custom profile directory
playwright-cli open --extension          # connect via browser extension
playwright-cli open --config=file.json   # use config file
```

## Configuration File

playwright-cli loads `.playwright/cli.config.json` automatically if present. Override with:

```bash
playwright-cli --config path/to/config.json open example.com
```

## Monitoring

Use the visual dashboard to observe running sessions:

```bash
playwright-cli show   # opens a live dashboard with all active sessions
```

## Read vs Write Operations

| Type | Operation | Behavior | Confirmation Prompt |
|------|-----------|----------|---------------------|
| **Read** | snapshot, screenshot, console, network, tab-list, cookie-list, localstorage-list | Automatic — no confirmation needed | — |
| **Write** | open, goto, click, fill, type, upload, state-save | Automatic for test/automation flows | — |
| **Destructive** | cookie-clear | Requires explicit user confirmation | "Clear all cookies for the current session?" |
| **Destructive** | localstorage-clear | Requires explicit user confirmation | "Clear all localStorage for the current session?" |
| **Destructive** | kill-all | Requires explicit user confirmation | "Kill all browser processes?" |

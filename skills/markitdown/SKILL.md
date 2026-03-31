---
name: Markitdown
description: |
  This skill should be used when the user asks to "convert this URL to markdown", "fetch page as markdown", "get this page as markdown", "convert this webpage", "summarize this URL", "turn this page into markdown", "fetch and convert", or wants to extract clean markdown content from a remote URL or data URI.
version: 1.0.0
---

# Markitdown Skill

Convert remote web pages, documents, and data URIs to clean, structured markdown using the `markitdown` MCP server. Useful for pulling external content into a readable format for analysis, capture, or agent pipelines.

## Operations

| Request | Action |
|---------|--------|
| "convert https://example.com to markdown" | Fetch and convert a URL |
| "get the Anthropic docs page as markdown" | Fetch a docs page |
| "convert this data URI to markdown" | Convert inline base64 content |
| "fetch this page and save to Obsidian" | Convert then pipe to capture skill |

## Tool

This skill uses a single MCP tool:

```
mcp__markitdown__convert_to_markdown(uri: string) → string
```

The `uri` must be one of:
- `https://` — remote URL (fetched at call time)
- `http://` — remote URL (plain HTTP)
- `data:` — inline base64-encoded content

## URI Constraints

### What works

| URI type | Example |
|----------|---------|
| HTTPS URL | `https://docs.anthropic.com/en/docs/...` |
| HTTP URL | `http://example.com` |
| Data URI | `data:text/html;base64,<base64content>` |
| Local file | Use `tools/markitdown.sh` (see below) |

### Local files — use the helper script

The MCP server runs in a Docker container with no volume mounts, so `file://` URIs passed directly to `mcp__markitdown__convert_to_markdown` will fail. For local files, use the bundled script instead:

```bash
tools/markitdown.sh <path-to-file>
```

The script resolves the absolute path, mounts the file's parent directory into the container as `/data`, and passes `file:///data/<filename>` to markitdown. Output is printed to stdout.

**Supported local file types include:** PDF, DOCX, PPTX, XLSX, HTML, CSV, JSON, XML, images with OCR, and plain text.

## Markitdown vs. WebFetch

Use this skill over a plain web fetch when:
- The page contains **tables** — markitdown preserves them as markdown tables
- The URL points to a **PDF or Office document** (markitdown handles binary formats)
- You need **structured output** for downstream processing (e.g. feeding into a prompt or saving to Obsidian)
- The page has heavy rendering and you want clean, noise-free content

Use a plain web fetch when:
- You only need a quick text extract from a simple HTML page
- The markitdown MCP server is unavailable

## Execution Steps

### 1. Extract the URI

Parse the URI from the user's request. If no URI is provided, ask for one.

### 2. Validate URI scheme

Check the scheme is `https://`, `http://`, or `data:`.

If the user provides a local file path (or a `file://` URI), use the helper script instead of the MCP tool:

```bash
${CLAUDE_PLUGIN_ROOT}/tools/markitdown.sh <file-path>
```

### 3. Call the tool

```
mcp__markitdown__convert_to_markdown(uri: "<uri>")
```

### 4. Present the result

Return the markdown content. For long pages, summarise the structure first:

```markdown
**Converted:** https://example.com/page

_~320 lines of markdown • includes 3 tables and 8 headings_

---

[markdown content]
```

### 5. Offer follow-up actions

After a successful conversion, suggest relevant next steps based on context:

- "Capture this to Obsidian" → use the capture skill
- "Summarise this" → pass the markdown to a follow-up prompt
- "Search my notes for related content" → use the research skill

## Error Handling

### Docker not running

```markdown
**Markitdown server unavailable**

The markitdown MCP server requires Docker. Please ensure:
1. Docker Desktop is running
2. The image is available: `docker pull mcp/markitdown:latest`
3. Restart Claude Code to reconnect the MCP server
```

### URL unreachable / fetch error

```markdown
**Could not fetch the URL**

Possible causes:
- The URL requires authentication or is behind a login wall
- The server is down or the URL is incorrect
- Network connectivity issue

Try opening the URL in a browser to verify it's accessible.
```

### Empty or unsupported content

```markdown
**No content extracted**

The page may be:
- A single-page app that requires JavaScript rendering (markitdown fetches static HTML only)
- An image-only page with no extractable text
- A binary format not supported by markitdown

Try a different URL or copy the text content manually.
```

## Integration with Other Skills

### Convert and Capture

Combine with the `capture` skill to save a converted page to Obsidian:

1. Convert the URL with `mcp__markitdown__convert_to_markdown`
2. Pass the markdown to the capture skill with a target note

### Convert and Research

After converting, use the `research` skill to find related notes in the vault that complement the fetched content.

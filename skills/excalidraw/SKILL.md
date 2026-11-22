---
name: excalidraw
description: |
  This skill should be used when the user asks to "create a diagram", "draw a flowchart", "sequence diagram", "architecture diagram", "visualise this", "diagram this flow", "draw in excalidraw", "excalidraw diagram", "sketch this", "whiteboard this", "hand-drawn diagram", "export to excalidraw", "save as .excalidraw", "share an excalidraw link", or any request to visually represent a system, process, or data model. This is the default diagram skill; use the mermaid skill only when the user specifically asks for Mermaid or Excalidraw is unavailable.
version: 1.0.0
---

# Excalidraw Diagrams Skill

Draw diagrams on a live Excalidraw canvas through the `excalidraw` MCP server (`mcp__excalidraw__*` tools). Output is a visual, hand-drawn-style diagram the user can keep editing in Excalidraw, export as `.excalidraw` / `.excalidraw.md`, or share by link.

## Mermaid or Excalidraw?

**Excalidraw is the default** for any diagram request. Use the **mermaid** skill instead only when:

- the user specifically asks for Mermaid, or
- Excalidraw is not available (see Prerequisites).

If the user needs the diagram as diffable text inside Markdown, they can ask for Mermaid; otherwise stay here.

## Prerequisites

The `excalidraw` MCP server (e.g. `mcp-excalidraw-server`) must be configured **and** connected to a running canvas server. It is not bundled in the plugin's `.mcp.json` because it needs a canvas to talk to — see `docs/configuration.md`.

Before drawing, check that the `mcp__excalidraw__*` tools are available (load them via ToolSearch if deferred). If they are not, or the canvas is unreachable, say so in one line and fall back to the **mermaid** skill, mentioning `docs/configuration.md` for setup. Do not invent `.excalidraw` JSON by hand unless the user asks for a file and accepts that it is unverified.

## Workflow

### 1. Understand the Diagram

Ask **one question at a time**. Skip clarification when the request is already specific (e.g. "architecture diagram of web → API → Postgres, with a queue on the side").

Focus on:
- **What is shown** — architecture, flow, data model, concept map?
- **Components and relationships** — what connects to what, sync or async?

### 2. Read the Design Guide

Call `mcp__excalidraw__read_diagram_guide` once per diagram session before creating anything. It returns the current palette, sizing rules, and per-type templates. Follow it rather than relying on remembered values.

### 3. Draw

1. If the canvas already has content, call `describe_scene`. Ask before `clear_canvas` — never wipe someone's work silently. Take a `snapshot_scene` first if you intend to replace it.
2. Create elements in this order with `batch_create_elements`:
   1. Background zones (large light rectangles)
   2. Shapes with labels in `text`, each with a custom `id`
   3. Arrows bound via `startElementId` / `endElementId` — never hand-place arrow coordinates
   4. Title and annotations
3. For a quick start from existing structure, `create_from_mermaid` converts Mermaid to editable Excalidraw elements. Use it for flowcharts and sequence diagrams, then refine.
4. Tidy with `align_elements` / `distribute_elements`.

**Conventions** (from the guide): fonts ≥ 16, 40–80px gaps, 3–4 fill colors max, dashed arrows for async/optional flows, same-role shapes the same size.

**Learned from running it against `mcp-excalidraw-server`:**
- **Solid fills aren't settable.** The guide recommends `fillStyle: "solid"`, but `batch_create_elements` and `update_element` don't accept it, so fills render hachured. Don't rely on it; the pastel `backgroundColor` pairs still read fine.
- **Diamonds need to be big.** The guide's 100×100 clips labels. Use about 260×130 for a two-line label.
- **Arrow labels need room.** Leave at least 80px (120px+ for labelled arrows) between connected shapes, or the label sits on top of the shape edge. Arrows need `x`/`y` in the call, but bound arrows re-route to the shape edges, so approximate values are fine.
- **Moving a shape doesn't re-route its arrows.** After `update_element` changes `x`/`y`, move shapes only along the arrow's axis, or delete and recreate the arrows.
- **Prefix ids** (e.g. `sk-`) on everything you create so you can screenshot or delete just your elements with `elementIds` / `delete_element`.
- **Share the canvas politely.** A non-empty canvas often belongs to someone else's work. Rather than clearing it, `snapshot_scene`, then draw in empty space to the right of the existing bounding box (from `describe_scene`).
- **Screenshot only your elements** with `get_canvas_screenshot` and `elementIds` plus `padding: 30` to verify without the rest of the canvas in the way.

### 4. Verify

Call `get_canvas_screenshot` and look at it. Check for overlapping elements, clipped labels, unbound arrows, and crossed lines. Fix and re-check. Do not report a diagram as done without viewing it.

Then ask: "Does this look right? I can adjust the layout, add detail, or export it."

### 5. Export (Confirmation Required)

| Option | Tool | Confirmation prompt |
|--------|------|---------------------|
| Save `.excalidraw` JSON | `export_scene` with `filePath` | "Write this to `<path>`?" |
| Save for Obsidian (`.excalidraw.md`) | `export_scene` with a `.md` path | "Write this to `<path>`?" |
| PNG / SVG | `export_to_image` | "Write this to `<path>`?" |
| Shareable link | `export_to_excalidraw_url` | "This uploads the diagram (encrypted) to excalidraw.com, and anyone with the link can view it. Create the link?" |

Defaults for saved files: `docs/diagrams/<topic>.excalidraw`. Create `docs/diagrams/` if missing. If the target already exists, do not overwrite silently — ask whether to replace it or choose another name. Only proceed after the user confirms.

The shareable link publishes content externally, so check the diagram contains nothing sensitive (internal hostnames, customer names) before asking.

## Integration with Other Skills

- **Brainstorming** — when a spec in `docs/specs/` has an architecture or flow section, offer an Excalidraw version if the user prefers visuals over Mermaid.
- **Mermaid** — hand off when the user asks for Mermaid, or when Excalidraw is unavailable.

## Error Handling

**Tools unavailable / canvas unreachable:** Report that the `excalidraw` MCP server or its canvas server is not connected, point to `docs/configuration.md`, and fall back to the mermaid skill. Do not retry in a loop.

**Overlapping or cramped layout:** Increase spacing, use `distribute_elements`, or split into several smaller diagrams.

**Arrows not attaching:** Confirm both shapes have custom `id`s and the arrow references them in `startElementId` / `endElementId`.

**Diagram too large to read:** Split by subsystem, or use frames/zones to group related elements.

**Wrong result:** `restore_snapshot` rolls the canvas back to a snapshot taken earlier.

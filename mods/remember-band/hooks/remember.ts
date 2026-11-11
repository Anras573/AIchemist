// Pure helpers for the remember band: no `$`, so tests call them directly.
// They read what the Remember plugin (Digital-Process-Tools/claude-remember)
// leaves on disk; none of them write anything.

import type { Handoff } from '../types'

type InstallEntry = { installPath?: unknown; projectPath?: unknown }

// Where Remember is installed, from Claude Code's installed_plugins.json
// (`{ version: 2, plugins: { "remember@<marketplace>": [{ installPath, ... }] } }`).
// Any marketplace counts: Remember ships from its own and from Anthropic's.
// A project-scoped install for this project wins over a user-wide one.
export function findRememberRoot(installedJson: string, projectRoot: string): string | null {
  let raw: unknown
  try {
    raw = JSON.parse(installedJson)
  } catch {
    return null
  }
  const plugins = (raw as { plugins?: unknown } | null)?.plugins
  if (plugins === null || typeof plugins !== 'object' || Array.isArray(plugins)) {
    return null
  }

  const entries: InstallEntry[] = []
  for (const [id, value] of Object.entries(plugins as Record<string, unknown>)) {
    if (!id.startsWith('remember@')) {
      continue
    }
    // Version 2 holds a list per plugin; version 1 held a single entry.
    for (const entry of Array.isArray(value) ? value : [value]) {
      if (entry !== null && typeof entry === 'object' && typeof (entry as InstallEntry).installPath === 'string') {
        entries.push(entry as InstallEntry)
      }
    }
  }

  const own = entries.find(e => e.projectPath === projectRoot)
  const global = entries.find(e => typeof e.projectPath !== 'string')
  const chosen = own ?? global

  return chosen ? (chosen.installPath as string) : null
}

export type RememberDir = { dir: string; isInProject: boolean }

// What `scripts/doctor.sh --json` prints. Remember marks that output as
// provisional, so anything but schema_version 1 is treated as unknown.
export function parseDoctor(stdout: string): RememberDir | null {
  let raw: unknown
  try {
    raw = JSON.parse(stdout.trim())
  } catch {
    return null
  }
  const doc = raw as { schema_version?: unknown; state?: unknown; remember_dir?: unknown; storage_mode?: unknown }
  if (doc === null || typeof doc !== 'object' || doc.schema_version !== 1) {
    return null
  }
  if (doc.state !== 'resolved' && doc.state !== 'resolved_assumed_project_dir') {
    return null
  }
  if (typeof doc.remember_dir !== 'string' || doc.remember_dir === '') {
    return null
  }

  return { dir: doc.remember_dir.replace(/[\\/]+$/, ''), isInProject: doc.storage_mode !== 'external' }
}

const HANDOFF_NAME = /^remember(\.[A-Za-z0-9._-]+)?\.md$/

// The handoff file Remember's session start published in tmp/handoff-path
// (or tmp/handoff-path.<session-id>). The hint is only trusted when it names
// a remember*.md directly inside the store; otherwise the plain remember.md.
export function handoffPath(hint: string | null, dir: string): string {
  const fallback = `${dir}/remember.md`
  const path = hint?.trim()
  if (!path) {
    return fallback
  }
  const cut = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'))
  const folder = path.slice(0, Math.max(0, cut)).replace(/\\/g, '/')
  const name = path.slice(cut + 1)

  return folder === dir.replace(/\\/g, '/') && HANDOFF_NAME.test(name) ? path : fallback
}

// The delivery record that goes with a handoff file: tmp/remember.delivered,
// or tmp/remember.delivered.<session-id> for a per-session remember.<id>.md.
export function deliveryPath(handoff: string, dir: string): string {
  const name = handoff.slice(Math.max(handoff.lastIndexOf('/'), handoff.lastIndexOf('\\')) + 1)
  const id = HANDOFF_NAME.exec(name)?.[1]

  return `${dir}/tmp/remember.delivered${id ?? ''}`
}

export type Delivery = { fingerprint: string; firstDelivered: string; deliveries: number }

// `fingerprint=…`, `first_delivered=…`, `deliveries=…`, one per line.
export function parseDelivery(text: string): Delivery {
  const fields = new Map<string, string>()
  for (const line of text.split(/\r?\n/)) {
    const at = line.indexOf('=')
    if (at > 0) {
      fields.set(line.slice(0, at).trim(), line.slice(at + 1).trim())
    }
  }
  const count = Number.parseInt(fields.get('deliveries') ?? '', 10)

  return {
    fingerprint: fields.get('fingerprint') ?? '',
    firstDelivered: fields.get('first_delivered') ?? '',
    deliveries: Number.isFinite(count) && count > 0 ? count : 0,
  }
}

// Remember fingerprints a handoff as `cksum < file | tr ' ' '-'`, i.e.
// `<crc>-<size>`. `cksum <file>` prints `<crc> <size> <file>`.
export function cksumFingerprint(stdout: string): string | null {
  const [crc, size] = stdout.trim().split(/\s+/)

  return crc && size ? `${crc}-${size}` : null
}

function clean(text: string): string {
  return text
    .replace(/`([^`]*)`/g, '$1')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\s+/g, ' ')
    .trim()
}

// The items under `## Next` in a handoff written by /remember. List items
// at the top level only; a checked `[x]` item is done and skipped. Without a
// list, each non-empty line of the section is an item.
export function parseNext(markdown: string): string[] {
  const lines = markdown.split(/\r?\n/)
  const start = lines.findIndex(line => /^#{1,6}\s*next\b/i.test(line.trim()))
  if (start < 0) {
    return []
  }
  const section: string[] = []
  for (const line of lines.slice(start + 1)) {
    if (/^#{1,6}\s/.test(line.trim())) {
      break
    }
    section.push(line)
  }

  const items: string[] = []
  let hasList = false
  for (const line of section) {
    const item = /^ ?(?:[-*+]|\d+[.)])\s+(.*)$/.exec(line)
    if (!item) {
      continue
    }
    hasList = true
    const box = /^\[( |x|X)\]\s*(.*)$/.exec(item[1]!)
    if (box && box[1] !== ' ') {
      continue
    }
    const text = clean(box ? box[2]! : item[1]!)
    if (text !== '') {
      items.push(text)
    }
  }
  if (hasList) {
    return items
  }

  return section
    .map(clean)
    .filter(text => text !== '' && !/^no active work\.?$/i.test(text) && !/^\{.*\}$/.test(text))
}

function truncate(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, Math.max(1, max - 1))}…`
}

export function age(fromMs: number, nowMs: number): string {
  const minutes = Math.floor(Math.max(0, nowMs - fromMs) / 60_000)
  if (minutes < 1) {
    return 'just now'
  }
  if (minutes < 60) {
    return `${minutes}m ago`
  }
  const hours = Math.floor(minutes / 60)
  if (hours < 24) {
    return `${hours}h ago`
  }

  return `${Math.floor(hours / 24)}d ago`
}

// Up to two lines, each fitting `columns` cells: the open items, and a note
// when an earlier session already loaded this same handoff. Empty when the
// note has nothing under `## Next`.
export function bandLines(handoff: Handoff, columns: number, nowMs: number): string[] {
  if (handoff.next.length === 0) {
    return []
  }
  const lines: string[] = []
  const itemMax = Math.max(12, Math.floor(columns / 3))
  const shown = handoff.next.slice(0, 3).map(item => truncate(item, itemMax)).join(' · ')
  const more = handoff.next.length > 3 ? ` · +${handoff.next.length - 3} more` : ''
  lines.push(
    truncate(`↪ Next (${handoff.next.length}, handoff ${age(handoff.writtenMs, nowMs)}): ${shown}${more}`, columns),
  )

  if (handoff.redelivered) {
    const { count, since } = handoff.redelivered
    const from = since ? ` since ${since}` : ''
    lines.push(truncate(`⚠ Same handoff loaded ${count}×${from}. /remember writes a new one`, columns))
  }

  return lines
}

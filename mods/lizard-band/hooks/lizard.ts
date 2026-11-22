// Pure helpers for the lizard band: no `$`, so tests call them directly.
//
// Inputs are what `git status --porcelain=v1 -z` and `lizard --csv` print.
// lizard's CSV has no header; the columns are
//   NLOC, CCN, token, PARAM, length, location, file, function, long_name, start, end
// and quoted fields may contain commas (long_name has the parameter list).

import type { Finding } from '../types'

// Paths of changed files that still exist, from `git status --porcelain=v1 -z`.
// An entry is `XY path`; a rename or copy is followed by one more entry holding
// the original path, which is skipped. Deleted files have nothing to scan.
export function parseChangedFiles(stdout: string): string[] {
  const entries = stdout.split('\0').filter(entry => entry !== '')
  const files: string[] = []

  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i]!
    const status = entry.slice(0, 2)
    const path = entry.slice(3)
    if (/[RC]/.test(status)) {
      i++
    }
    if (!status.includes('D') && path !== '') {
      files.push(path)
    }
  }

  return files
}

export function parseCsvLine(line: string): string[] {
  const fields: string[] = []
  let current = ''
  let quoted = false

  for (let i = 0; i < line.length; i++) {
    const ch = line[i]!
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') {
        current += '"'
        i++
      } else if (ch === '"') {
        quoted = false
      } else {
        current += ch
      }
    } else if (ch === '"') {
      quoted = true
    } else if (ch === ',') {
      fields.push(current)
      current = ''
    } else {
      current += ch
    }
  }
  fields.push(current)

  return fields
}

function toFinding(line: string): Finding | null {
  const f = parseCsvLine(line)
  const ccn = Number(f[1])
  const startLine = Number(f[9])
  if (f.length < 10 || !Number.isFinite(ccn) || !f[6] || !f[7]) {
    return null
  }

  return { file: f[6], name: f[7], ccn, line: Number.isFinite(startLine) ? startLine : 0 }
}

// Functions above `threshold`, most complex first (ties keep lizard's order).
export function parseFindings(stdout: string, threshold: number): Finding[] {
  return stdout
    .split('\n')
    .map(line => line.trim())
    .filter(line => line !== '')
    .map(toFinding)
    .filter((finding): finding is Finding => finding !== null && finding.ccn > threshold)
    .map((finding, index) => ({ finding, index }))
    .sort((a, b) => b.finding.ccn - a.finding.ccn || a.index - b.index)
    .map(({ finding }) => finding)
}

function truncate(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, Math.max(1, max - 1))}…`
}

function describe(finding: Finding, nameMax: number): string {
  return `${truncate(finding.name, nameMax)} CCN ${finding.ccn} ${finding.file}:${finding.line}`
}

// Up to two lines, each fitting `columns` cells; empty when nothing is flagged.
export function bandLines(findings: readonly Finding[], threshold: number, columns: number): string[] {
  if (findings.length === 0) {
    return []
  }

  const shown = findings.slice(0, 3).map(f => describe(f, 30)).join(' · ')
  const more = findings.length > 3 ? ` · +${findings.length - 3} more` : ''

  return [
    truncate(`🔥 Complexity > ${threshold} in changed files (${findings.length}): ${shown}${more}`, columns),
    truncate('Run /hotspot to weigh these against git churn', columns),
  ]
}

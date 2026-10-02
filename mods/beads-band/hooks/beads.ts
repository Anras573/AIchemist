// Pure helpers for the beads band: no `$`, so tests call them directly.
// Input is what `bd ready --json` and `bd list --status in_progress --json`
// print (bd 1.x): an array of issues with id, title, status and priority.

import type { BeadsTask } from '../types'

type RawIssue = {
  id?: unknown
  title?: unknown
  status?: unknown
  priority?: unknown
}

export function parseTasks(stdout: string): BeadsTask[] {
  let raw: unknown
  try {
    raw = JSON.parse(stdout)
  } catch {
    return []
  }
  if (!Array.isArray(raw)) {
    return []
  }

  return (raw as RawIssue[])
    .filter(issue => typeof issue.id === 'string' && typeof issue.title === 'string')
    .map(issue => ({
      id: issue.id as string,
      title: (issue.title as string).trim(),
      status: typeof issue.status === 'string' ? issue.status : 'open',
      priority: typeof issue.priority === 'number' ? issue.priority : 4,
    }))
    // bd priorities run 0 (highest) to 4; keep bd's order within a priority.
    .map((task, index) => ({ task, index }))
    .sort((a, b) => a.task.priority - b.task.priority || a.index - b.index)
    .map(({ task }) => task)
}

function truncate(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, Math.max(1, max - 1))}…`
}

function describe(task: BeadsTask, titleMax: number): string {
  return `P${task.priority} ${task.id} ${truncate(task.title, titleMax)}`
}

// Up to two lines: what is in progress, and what is ready next. Each fits
// `columns` cells; empty when there is nothing to show.
export function bandLines(
  inProgress: readonly BeadsTask[],
  ready: readonly BeadsTask[],
  columns: number,
): string[] {
  const lines: string[] = []
  const titleMax = Math.max(12, Math.floor(columns / 3))

  if (inProgress.length > 0) {
    const more = inProgress.length > 1 ? ` (+${inProgress.length - 1} more)` : ''
    lines.push(truncate(`▶ In progress: ${describe(inProgress[0]!, titleMax)}${more}`, columns))
  }

  // A task in progress is never also listed as ready.
  const busy = new Set(inProgress.map(t => t.id))
  const next = ready.filter(t => !busy.has(t.id))
  if (next.length > 0) {
    const shown = next.slice(0, 3).map(t => describe(t, titleMax)).join(' · ')
    const more = next.length > 3 ? ` · +${next.length - 3} more` : ''
    lines.push(truncate(`◇ Ready (${next.length}): ${shown}${more}`, columns))
  }

  return lines
}

// Pure helpers for the calendar status line: no `$`, so tests call them directly.
// Event shape is what `tools/msgraph.sh get-events` prints (Graph calendarView,
// trimmed by its $select).

export type GraphDateTime = {
  dateTime: string
  timeZone: string
}

export type GraphEvent = {
  id: string
  subject?: string | null
  start: GraphDateTime
  end: GraphDateTime
  sensitivity?: string
  isCancelled?: boolean
  isAllDay?: boolean
}

export type Meeting = {
  id: string
  title: string
  startMs: number
  endMs: number
}

const MINUTE = 60_000

// calendarView returns UTC wall-clock times without a zone suffix
// (`2026-05-11T07:00:00.0000000`, timeZone "UTC") unless a Prefer header
// asks otherwise, which msgraph.sh does not send.
export function toEpochMs(value: GraphDateTime): number {
  const hasZone = /(Z|[+-]\d{2}:\d{2})$/.test(value.dateTime)
  const suffix = !hasZone && value.timeZone === 'UTC' ? 'Z' : ''

  return Date.parse(value.dateTime + suffix)
}

// Graph rejects offsets without a colon, so spell UTC as +00:00 rather than
// relying on a local offset the hooks environment may not know.
export function toGraphIso(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, '+00:00')
}

export function parseMeetings(stdout: string): Meeting[] {
  const raw: unknown = JSON.parse(stdout)
  if (!Array.isArray(raw)) {
    return []
  }

  return (raw as GraphEvent[])
    .filter(event => !event.isCancelled && !event.isAllDay)
    .map(event => ({
      id: event.id,
      title:
        event.sensitivity === 'private'
          ? 'Private event'
          : event.subject?.trim() || '(no subject)',
      startMs: toEpochMs(event.start),
      endMs: toEpochMs(event.end),
    }))
    .filter(m => Number.isFinite(m.startMs) && Number.isFinite(m.endMs))
    .sort((a, b) => a.startMs - b.startMs)
}

export function formatDuration(ms: number): string {
  const minutes = Math.max(1, Math.ceil(ms / MINUTE))
  if (minutes < 60) {
    return `${minutes}m`
  }

  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60

  return rest === 0 ? `${hours}h` : `${hours}h ${rest}m`
}

function truncate(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`
}

// One line: what is on now, what is next, or nothing when the window is empty.
export function formatStatus(
  meetings: readonly Meeting[],
  nowMs: number,
  maxTitle = 40,
): string | undefined {
  const current = meetings.find(m => m.startMs <= nowMs && nowMs < m.endMs)
  const next = meetings.find(m => m.startMs > nowMs)
  const parts: string[] = []

  if (current) {
    parts.push(
      `Now: ${truncate(current.title, maxTitle)} (ends in ${formatDuration(current.endMs - nowMs)})`,
    )
  }
  if (next) {
    parts.push(
      `Next: ${truncate(next.title, maxTitle)} in ${formatDuration(next.startMs - nowMs)}`,
    )
  }

  return parts.length === 0 ? undefined : `📅 ${parts.join(' · ')}`
}

// Keyed on start time too, so a rescheduled meeting is announced again.
export function reminderKey(meeting: Meeting): string {
  return `${meeting.id}@${meeting.startMs}`
}

// Meetings starting within `leadMs` that have not been announced yet.
export function dueReminders(
  meetings: readonly Meeting[],
  nowMs: number,
  leadMs: number,
  announced: ReadonlySet<string>,
): Meeting[] {
  if (leadMs <= 0) {
    return []
  }

  return meetings.filter(
    m => m.startMs > nowMs && m.startMs - nowMs <= leadMs && !announced.has(reminderKey(m)),
  )
}

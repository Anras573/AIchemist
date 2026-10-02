import { describe, expect, mock, test } from 'claude-code/testing'

import {
  dueReminders,
  formatDuration,
  formatStatus,
  parseMeetings,
  toEpochMs,
  toGraphIso,
  type Meeting,
} from '../hooks/calendar'

const NOW = Date.parse('2026-10-02T09:00:00Z')
const MINUTE = 60_000

const graphEvent = (overrides: Record<string, unknown>) => ({
  id: 'e1',
  subject: 'Standup',
  start: { dateTime: '2026-10-02T09:15:00.0000000', timeZone: 'UTC' },
  end: { dateTime: '2026-10-02T09:30:00.0000000', timeZone: 'UTC' },
  sensitivity: 'normal',
  isCancelled: false,
  isAllDay: false,
  ...overrides,
})

const meeting = (id: string, startMin: number, endMin: number, title = id): Meeting => ({
  id,
  title,
  startMs: NOW + startMin * MINUTE,
  endMs: NOW + endMin * MINUTE,
})

describe('helpers', () => {
  test('reads Graph UTC times without a zone suffix as UTC', () => {
    expect(toEpochMs({ dateTime: '2026-10-02T09:15:00.0000000', timeZone: 'UTC' })).toBe(
      NOW + 15 * MINUTE,
    )
  })

  test('spells Graph query times with a +00:00 offset', () => {
    expect(toGraphIso(NOW)).toBe('2026-10-02T09:00:00+00:00')
  })

  test('drops cancelled and all-day events and hides private subjects', () => {
    const stdout = JSON.stringify([
      graphEvent({ id: 'b', start: { dateTime: '2026-10-02T11:00:00', timeZone: 'UTC' }, end: { dateTime: '2026-10-02T12:00:00', timeZone: 'UTC' }, sensitivity: 'private', subject: 'Doctor' }),
      graphEvent({ id: 'a' }),
      graphEvent({ id: 'c', isCancelled: true }),
      graphEvent({ id: 'd', isAllDay: true }),
    ])

    const parsed = parseMeetings(stdout)

    expect(parsed.map(m => m.id)).toEqual(['a', 'b'])
    expect(parsed[1]?.title).toBe('Private event')
  })

  test('formats durations in minutes and hours', () => {
    expect(formatDuration(30_000)).toBe('1m')
    expect(formatDuration(12 * MINUTE)).toBe('12m')
    expect(formatDuration(60 * MINUTE)).toBe('1h')
    expect(formatDuration(95 * MINUTE)).toBe('1h 35m')
  })

  test('shows the current and the next meeting', () => {
    const line = formatStatus([meeting('now', -10, 20, 'Planning'), meeting('next', 45, 60, '1:1')], NOW)

    expect(line).toBe('📅 Now: Planning (ends in 20m) · Next: 1:1 in 45m')
  })

  test('clears the line when nothing is on or coming up', () => {
    expect(formatStatus([meeting('past', -60, -30)], NOW)).toBeUndefined()
  })

  test('reminds once per meeting inside the lead time, and never when off', () => {
    const meetings = [meeting('soon', 2, 30), meeting('later', 20, 30)]

    expect(dueReminders(meetings, NOW, 2 * MINUTE, new Set()).map(m => m.id)).toEqual(['soon'])
    expect(dueReminders(meetings, NOW, 2 * MINUTE, new Set([`soon@${NOW + 2 * MINUTE}`]))).toEqual([])
    expect(dueReminders(meetings, NOW, 0, new Set())).toEqual([])
  })
})

describe('register', () => {
  const start = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const

  test('shows the next meeting fetched through calendar.sh', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mock.env(on, { MSGRAPH_APP_ID: 'app', MSGRAPH_TENANT_ID: 'tenant' })
    on('session.start', async (_$, e) => ({ cwd: e.cwd }))

    const runs: (readonly string[])[] = []
    on('process.run', async (_$, e) => {
      runs.push(e.argv)
      return {
        value: {
          exitCode: 0,
          stdout: JSON.stringify([graphEvent({})]),
          stderr: '',
          isStdoutTruncated: false,
          isStderrTruncated: false,
        },
      }
    })
    const statuses: (string | undefined)[] = []
    on('ui.status', async (_$, e) => {
      statuses.push(e.text)
      return { value: undefined }
    })
    on('ui.toast', async () => ({ value: undefined }))

    await $.session.start(start)
    await clock.advance(1)

    expect(runs[0]?.slice(2)).toEqual([
      'get-events',
      '--start',
      '2026-10-02T09:00:00+00:00',
      '--end',
      '2026-10-02T17:00:00+00:00',
    ])
    expect(runs[0]?.[1]).toMatch(/tools\/calendar\.sh$/)
    expect(statuses.at(-1)).toBe('📅 Next: Standup in 15m')
  })

  test('turns on for an iCloud/CalDAV setup too', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mock.env(on, { CALDAV_USERNAME: 'me@icloud.com' })
    on('session.start', async (_$, e) => ({ cwd: e.cwd }))

    const runs: (readonly string[])[] = []
    on('process.run', async (_$, e) => {
      runs.push(e.argv)
      return { value: { exitCode: 0, stdout: '[]', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    })
    on('ui.status', async () => ({ value: undefined }))

    await $.session.start(start)
    await clock.advance(1)

    expect(runs[0]?.[1]).toMatch(/tools\/calendar\.sh$/)
    expect(runs[0]?.[2]).toBe('get-events')
  })

  test('stays silent when the calendar skill is not configured', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mock.env(on, {})
    on('session.start', async (_$, e) => ({ cwd: e.cwd }))

    let ran = false
    on('process.run', async () => {
      ran = true
      throw new Error('should not run')
    })

    await $.session.start(start)
    await clock.advance(10 * MINUTE)

    expect(ran).toBe(false)
  })
})

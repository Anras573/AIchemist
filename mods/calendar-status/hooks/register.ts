import type { Register, Timer } from 'claude-code'

import {
  dueReminders,
  formatStatus,
  parseMeetings,
  reminderKey,
  toGraphIso,
  type Meeting,
} from './calendar'

const MINUTE = 60_000
const HOUR = 60 * MINUTE

// Shows the next meeting in the status line, read through the same
// tools/calendar.sh the calendar skill uses (Microsoft 365 or iCloud/CalDAV).
// Display only: the skill stays the source of truth and works the same
// without this mod.
export const register: Register = (on, options) => {
  const refreshMs = Math.max(1, Number(options.refreshMinutes ?? 5)) * MINUTE
  const lookaheadMs = Math.max(1, Number(options.lookaheadHours ?? 8)) * HOUR
  const reminderMs = Math.max(0, Number(options.reminderMinutes ?? 2)) * MINUTE

  let meetings: Meeting[] = []
  const announced = new Set<string>()
  let timers: Timer[] = []

  on('session.start', async ($, e, next) => {
    // Without either backend's variables the person has not set up the
    // calendar skill, so stay out of the way instead of showing an error.
    const hasMsgraph = Boolean((await $.env.get('MSGRAPH_APP_ID')) && (await $.env.get('MSGRAPH_TENANT_ID')))
    const hasCaldav = Boolean(await $.env.get('CALDAV_USERNAME'))
    if (!e.isInteractive || !(hasMsgraph || hasCaldav)) {
      return next(e)
    }

    const script = `${$.plugin.root}/tools/calendar.sh`

    const render = async () => {
      const now = await $.clock.now()
      $.ui.status(formatStatus(meetings, now))

      for (const meeting of dueReminders(meetings, now, reminderMs, announced)) {
        announced.add(reminderKey(meeting))
        $.ui.toast(`📅 ${meeting.title} starts in ${Math.ceil((meeting.startMs - now) / MINUTE)}m`)
      }
    }

    const refresh = async () => {
      const now = await $.clock.now()
      try {
        const { exitCode, stdout } = await $.process.run(
          [
            'bash',
            script,
            'get-events',
            '--start',
            toGraphIso(now),
            '--end',
            toGraphIso(now + lookaheadMs),
          ],
          { timeoutMs: MINUTE },
        )
        // On a failed fetch (expired login, offline) keep the last good list:
        // its countdowns stay right and past meetings drop off by themselves.
        if (exitCode === 0) {
          meetings = parseMeetings(stdout)
        }
      } catch {
        // Timed out or could not start; same as a failed fetch.
      }
      await render()
    }

    // session.start can fire again without a reload (an enable, a worker
    // respawn); drop the previous timers so they don't stack.
    for (const timer of timers) {
      timer.cancel()
    }
    timers = [
      $.clock.after(1, () => void refresh()),
      $.clock.every(refreshMs, () => void refresh()),
      $.clock.every(MINUTE, () => void render()),
    ]

    return next(e)
  })
}

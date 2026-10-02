import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { BeadsSnapshot } from '../types'
import { bandLines, parseTasks } from './beads'

const COMMAND = 'beads-band'

const snapshot = atom({ plugin: 'aichemist-beads-band', key: 'snapshot' } as const, null as BeadsSnapshot | null)
const isHidden = atom({ plugin: 'aichemist-beads-band', key: 'isHidden' } as const, false)

// Re-reads the database through the beads skill's own tools/beads-db.sh, so
// the band always shows the database the skill uses. Read-only throughout:
// the script runs without --init and every bd call passes --readonly, so a
// repo or sidecar the skill has not set up stays untouched.
async function refresh($: EngineInterface): Promise<void> {
  const next = await fetchSnapshot($)
  await update($, snapshot, () => next)
}

async function fetchSnapshot($: EngineInterface): Promise<BeadsSnapshot | null> {
  try {
    const resolved = await $.process.run(['bash', `${$.plugin.root}/tools/beads-db.sh`])
    // Exit 3: no database for this repo yet. Anything else non-zero: the
    // script failed. Either way there is nothing to show.
    const db = resolved.stdout.trim()
    if (resolved.exitCode !== 0 || db === '') {
      return null
    }

    // One at a time: bd's embedded Dolt takes a lock per call.
    const inProgress = await $.process.run(['bd', '--db', db, '--readonly', 'list', '--status', 'in_progress', '--json'])
    const ready = await $.process.run(['bd', '--db', db, '--readonly', 'ready', '--json'])
    if (inProgress.exitCode !== 0 || ready.exitCode !== 0) {
      return null
    }

    return { inProgress: parseTasks(inProgress.stdout), ready: parseTasks(ready.stdout) }
  } catch {
    // bd or bash missing, or a call timed out.
    return null
  }
}

export const register: Register = (on, options) => {
  const refreshMs = Math.max(15, Number(options.refreshSeconds ?? 60)) * 1000
  let poll: Timer | undefined

  on('session.start', async ($, e, next) => {
    if (!e.isInteractive) {
      return next(e)
    }

    await $.command.register({
      name: COMMAND,
      description: 'Show or hide the beads band (in-progress and ready tasks above the prompt)',
    })
    // session.start can fire again without a reload; don't stack timers.
    poll?.cancel()
    poll = $.clock.every(refreshMs, () => void refresh($))
    $.clock.after(1, () => void refresh($))

    return next(e)
  })

  // Claude often changes tasks during a turn (claim, close, create), so read
  // again once each turn ends.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    void refresh($)

    return result
  })

  on('command.run', { command: COMMAND }, async $ => {
    const hidden = !(await read($, isHidden))
    await update($, isHidden, () => hidden)
    if (!hidden) {
      void refresh($)
    }

    return { text: hidden ? 'Beads band hidden. Run /beads-band to show it again.' : 'Beads band shown.' }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const tasks = await read($, snapshot)
    if (e.props.hasSurvey || tasks === null || (await read($, isHidden))) {
      return next(e)
    }

    const lines = bandLines(tasks.inProgress, tasks.ready, Math.max(20, e.props.bodyColumns - 10))
    if (lines.length === 0) {
      return next(e)
    }

    const { Box, Button, Text } = $.ui.resolve(e)
    const shown = lines.slice(0, Math.max(1, e.props.maxRows))

    return (
      <Box flexDirection="row" justifyContent="space-between">
        <Box flexDirection="column" flexGrow={1}>
          {shown.map((line, index) => (
            <Text key={`line-${index}`} dimColor={!line.startsWith('▶')} wrap="truncate-end">
              {line}
            </Text>
          ))}
        </Box>
        <Button key="hide" hotkey="h" dimColor label="Hide" onPress={() => update($, isHidden, () => true)} />
      </Box>
    )
  })
}

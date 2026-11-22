import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { LizardSnapshot } from '../types'
import { bandLines, parseChangedFiles, parseFindings } from './lizard'

const COMMAND = 'lizard-band'
// Keeps one lizard run short in a big working tree.
const MAX_FILES = 100

const snapshot = atom({ plugin: 'aichemist-lizard-band', key: 'snapshot' } as const, null as LizardSnapshot | null)
const isHidden = atom({ plugin: 'aichemist-lizard-band', key: 'isHidden' } as const, false)

// Read-only throughout: `git status` and `lizard` (the tool the hotspot skill
// uses) only read. No shell is involved; paths go in as separate arguments
// after `--`, so a file name can never be taken for an option.
async function scan($: EngineInterface, threshold: number): Promise<LizardSnapshot | null> {
  try {
    const top = await $.process.run(['git', 'rev-parse', '--show-toplevel'])
    const root = top.stdout.trim()
    if (top.exitCode !== 0 || root === '') {
      return null
    }

    const status = await $.process.run(['git', 'status', '--porcelain=v1', '-z', '--untracked-files=all'], { cwd: root })
    if (status.exitCode !== 0) {
      return null
    }
    const files = parseChangedFiles(status.stdout).slice(0, MAX_FILES)
    if (files.length === 0) {
      return { scanned: 0, threshold, findings: [] }
    }

    const lizard = await $.process.run(['lizard', '--csv', '--', ...files], { cwd: root })
    if (lizard.exitCode !== 0) {
      return null
    }

    return { scanned: files.length, threshold, findings: parseFindings(lizard.stdout, threshold) }
  } catch {
    // git or lizard missing, or a call timed out.
    return null
  }
}

// One scan at a time; the module's variables start over on a reload, which is fine.
let scanning = false

async function refresh($: EngineInterface, threshold: number): Promise<void> {
  if (scanning) {
    return
  }
  scanning = true
  try {
    const next = await scan($, threshold)
    await update($, snapshot, () => next)
  } finally {
    scanning = false
  }
}

export const register: Register = (on, options) => {
  const refreshMs = Math.max(15, Number(options.refreshSeconds ?? 60)) * 1000
  const threshold = Math.max(2, Number(options.ccnThreshold ?? 15))
  let poll: Timer | undefined

  on('session.start', async ($, e, next) => {
    if (!e.isInteractive) {
      return next(e)
    }

    await $.command.register({
      name: COMMAND,
      description: 'Show or hide the lizard band (complex functions in your uncommitted changes)',
    })
    // session.start can fire again without a reload; don't stack timers.
    poll?.cancel()
    poll = $.clock.every(refreshMs, () => void refresh($, threshold))
    $.clock.after(1, () => void refresh($, threshold))

    return next(e)
  })

  // Claude edits files during a turn, so scan again once each turn ends.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    void refresh($, threshold)

    return result
  })

  on('command.run', { command: COMMAND }, async $ => {
    const hidden = !(await read($, isHidden))
    await update($, isHidden, () => hidden)
    if (!hidden) {
      void refresh($, threshold)
    }

    return { text: hidden ? 'Lizard band hidden. Run /lizard-band to show it again.' : 'Lizard band shown.' }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const state = await read($, snapshot)
    if (e.props.hasSurvey || state === null || (await read($, isHidden))) {
      return next(e)
    }

    const lines = bandLines(state.findings, state.threshold, Math.max(20, e.props.bodyColumns - 10))
    if (lines.length === 0) {
      return next(e)
    }

    const { Box, Button, Text } = $.ui.resolve(e)
    const shown = lines.slice(0, Math.max(1, e.props.maxRows))

    return (
      <Box flexDirection="row" justifyContent="space-between">
        <Box flexDirection="column" flexGrow={1}>
          {shown.map((line, index) => (
            <Text key={`line-${index}`} dimColor={index > 0} wrap="truncate-end">
              {line}
            </Text>
          ))}
        </Box>
        <Button key="hide" hotkey="l" dimColor label="Hide" onPress={() => update($, isHidden, () => true)} />
      </Box>
    )
  })
}

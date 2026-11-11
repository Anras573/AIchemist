import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { Handoff } from '../types'
import {
  bandLines,
  cksumFingerprint,
  deliveryPath,
  findRememberRoot,
  handoffPath,
  parseDelivery,
  parseDoctor,
  parseNext,
} from './remember'
import type { RememberDir } from './remember'

const COMMAND = 'remember-band'
const SAFE_SESSION_ID = /^[A-Za-z0-9._-]+$/

const handoff = atom({ plugin: 'aichemist-remember-band', key: 'handoff' } as const, null as Handoff | null)
const isHidden = atom({ plugin: 'aichemist-remember-band', key: 'isHidden' } as const, false)

// Where Remember keeps this project's memory, asked once per project root.
// Remember's own `doctor.sh --json` answers it, so the band never recomputes
// Remember's slug or storage-mode rules.
type Cache = { located: { root: string; store: RememberDir } | null }

async function locate($: EngineInterface, cache: Cache, root: string, sessionId: string): Promise<RememberDir | null> {
  if (cache.located?.root === root) {
    return cache.located.store
  }

  const configDir = (await $.env.get('CLAUDE_CONFIG_DIR')) || `${await $.env.get('HOME')}/.claude`
  const installed = await $.fs.read(`${configDir}/plugins/installed_plugins.json`).catch(() => null)
  const plugin = typeof installed === 'string' ? findRememberRoot(installed, root) : null
  if (plugin === null || !(await $.fs.exists(`${plugin}/scripts/doctor.sh`))) {
    return null
  }

  const env: Record<string, string> = { CLAUDE_PROJECT_DIR: root }
  if (SAFE_SESSION_ID.test(sessionId)) {
    env.CLAUDE_CODE_SESSION_ID = sessionId
  }
  const doctor = await $.process.run(['bash', `${plugin}/scripts/doctor.sh`, '--json'], {
    cwd: root,
    env,
    timeoutMs: 15_000,
  })
  const store = doctor.exitCode === 0 ? parseDoctor(doctor.stdout) : null
  if (store !== null) {
    cache.located = { root, store }
  }

  return store
}

async function readOrNull($: EngineInterface, path: string): Promise<string | null> {
  const text = await $.fs.read(path).catch(() => null)

  return typeof text === 'string' ? text : null
}

// Read-only throughout: the band reads Remember's files and runs its
// read-only `doctor.sh --json`, and never writes to the memory store.
async function fetchHandoff($: EngineInterface, cache: Cache): Promise<Handoff | null> {
  try {
    const root = await $.session.root()
    const sessionId = await $.session.id()
    const store = await locate($, cache, root, sessionId)
    if (store === null) {
      return null
    }

    // The handoff file Remember's session start resolved for this session.
    const hint =
      (SAFE_SESSION_ID.test(sessionId) ? await readOrNull($, `${store.dir}/tmp/handoff-path.${sessionId}`) : null) ??
      (await readOrNull($, `${store.dir}/tmp/handoff-path`))
    const path = handoffPath(hint, store.dir)

    // Same refusals as Remember's loader: never a symlink, and never a
    // handoff the project's git repository tracks (one a repo shipped, not
    // one your /remember wrote).
    const stat = await $.fs.stat(path).catch(() => null)
    if (stat === null || stat.isLink || stat.kind !== 'file' || stat.size === 0) {
      return null
    }
    if (store.isInProject) {
      const tracked = await $.process.run(['git', '-C', store.dir, 'ls-files', '--error-unmatch', '--', path])
      if (tracked.exitCode === 0) {
        return null
      }
    }

    const text = await readOrNull($, path)
    if (text === null) {
      return null
    }

    // Remember counts how many sessions have loaded this exact note. Only
    // trust the count while the note is still the one it fingerprinted.
    let redelivered: Handoff['redelivered'] = null
    const record = await readOrNull($, deliveryPath(path, store.dir))
    const delivery = record === null ? null : parseDelivery(record)
    if (delivery !== null && delivery.deliveries >= 2) {
      const sum = await $.process.run(['cksum', path])
      const fingerprint = sum.exitCode === 0 ? cksumFingerprint(sum.stdout) : null
      if (fingerprint !== null && delivery.fingerprint === fingerprint) {
        redelivered = { count: delivery.deliveries, since: delivery.firstDelivered }
      }
    }

    return { next: parseNext(text), writtenMs: stat.mtimeMs, redelivered }
  } catch {
    // bash, git or cksum missing, or a call timed out.
    return null
  }
}

async function refresh($: EngineInterface, cache: Cache): Promise<void> {
  const next = await fetchHandoff($, cache)
  await update($, handoff, () => next)
}

export const register: Register = (on, options) => {
  const refreshMs = Math.max(15, Number(options.refreshSeconds ?? 60)) * 1000
  const cache: Cache = { located: null }
  let poll: Timer | undefined


  on('session.start', async ($, e, next) => {
    if (!e.isInteractive) {
      return next(e)
    }

    await $.command.register({
      name: COMMAND,
      description: 'Show or hide the remember band (open items from the last /remember handoff)',
    })
    // session.start can fire again without a reload; don't stack timers.
    poll?.cancel()
    poll = $.clock.every(refreshMs, () => void refresh($, cache))
    // Give Remember's own SessionStart hook a moment to publish this
    // session's handoff path first.
    $.clock.after(2000, () => void refresh($, cache))

    return next(e)
  })

  // /remember writes a new handoff during a turn; read again once it ends.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    void refresh($, cache)

    return result
  })

  on('command.run', { command: COMMAND }, async $ => {
    const hidden = !(await read($, isHidden))
    await update($, isHidden, () => hidden)
    if (!hidden) {
      void refresh($, cache)
    }

    return { text: hidden ? 'Remember band hidden. Run /remember-band to show it again.' : 'Remember band shown.' }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const note = await read($, handoff)
    if (e.props.hasSurvey || note === null || (await read($, isHidden))) {
      return next(e)
    }

    const lines = bandLines(note, Math.max(20, e.props.bodyColumns - 10), await $.clock.now())
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
        <Button key="hide" hotkey="m" dimColor label="Hide" onPress={() => update($, isHidden, () => true)} />
      </Box>
    )
  })
}

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { PrSnapshot } from '../types'
import {
  PR_VIEW_FIELDS,
  THREADS_QUERY,
  describeGhError,
  formatAgo,
  parseSnapshot,
  repoFromUrl,
} from './github'

const PANE = 'pr-review'
const COMMAND = 'pr-pane'

const snapshot = atom({ plugin: 'aichemist-pr-review-pane', key: 'snapshot' } as const, null as PrSnapshot | null)
const error = atom({ plugin: 'aichemist-pr-review-pane', key: 'error' } as const, null as string | null)
const isLoading = atom({ plugin: 'aichemist-pr-review-pane', key: 'isLoading' } as const, false)
const prNumber = atom({ plugin: 'aichemist-pr-review-pane', key: 'prNumber' } as const, null as number | null)

const STATE_COLOR = { WAITING: 'yellow', REVIEWING: 'cyan', DONE: 'green' } as const
const STATE_TEXT = {
  WAITING: 'waiting for Copilot to review the latest commit',
  REVIEWING: 'Copilot has reviewed; threads to address',
  DONE: 'Copilot has reviewed; nothing left open',
} as const

async function fetchSnapshot($: EngineInterface): Promise<void> {
  if (await read($, isLoading)) {
    return
  }
  await update($, isLoading, () => true)

  try {
    const pinned = await read($, prNumber)
    const view = await $.process.run([
      'gh',
      'pr',
      'view',
      ...(pinned === null ? [] : [String(pinned)]),
      '--json',
      PR_VIEW_FIELDS,
    ])
    if (view.exitCode !== 0) {
      await update($, error, () => describeGhError(view.stderr))
      return
    }

    const pr = JSON.parse(view.stdout) as { number: number; url: string; headRefOid: string }
    const repo = repoFromUrl(pr.url)
    if (!repo) {
      await update($, error, () => `Could not read the repository from ${pr.url}.`)
      return
    }

    const threads = await $.process.run([
      'gh',
      'api',
      'graphql',
      '-f',
      `query=${THREADS_QUERY}`,
      '-F',
      `owner=${repo.owner}`,
      '-F',
      `repo=${repo.repo}`,
      '-F',
      `pr=${pr.number}`,
      '-F',
      `oid=${pr.headRefOid}`,
    ])
    if (threads.exitCode !== 0) {
      await update($, error, () => describeGhError(threads.stderr))
      return
    }

    const next = parseSnapshot(view.stdout, threads.stdout, await $.clock.now())
    await update($, snapshot, () => next)
    await update($, error, () => null)
  } catch (caught) {
    // gh missing, timed out, or printed something that is not JSON.
    const message = caught instanceof Error ? caught.message : String(caught)
    await update($, error, () => `Could not run gh: ${message}`)
  } finally {
    await update($, isLoading, () => false)
  }
}

async function isOpen($: EngineInterface): Promise<boolean> {
  return (await $.ui.panes()).some(pane => pane.id === PANE)
}

async function openPane($: EngineInterface): Promise<void> {
  await $.ui.open({ id: PANE, title: 'PR review' })
  void fetchSnapshot($)
}

// A read-only view of what skills/pr-review-loop works on: the PR for the
// current branch, Copilot's review state, CI and the unresolved threads. It
// never writes to GitHub; fixing stays the skill's job.
export const register: Register = (on, options) => {
  const refreshMs = Math.max(15, Number(options.refreshSeconds ?? 60)) * 1000
  let poll: Timer | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: COMMAND,
      description: 'Show the PR review state (Copilot review, CI, unresolved threads) in a pane',
      argumentHint: '[pr-number]',
    })
    // State outlives a reload; a fetch cut off by one must not block the next.
    await update($, isLoading, () => false)
    // Polls only while the pane is open, so a closed pane costs nothing.
    // session.start can fire again without a reload; don't stack timers.
    poll?.cancel()
    poll = $.clock.every(refreshMs, () => {
      void isOpen($).then(open => (open ? fetchSnapshot($) : undefined))
    })

    return next(e)
  })

  on('command.run', { command: COMMAND }, async ($, e) => {
    const arg = e.args.trim().replace(/^#/, '')
    const pinned = /^\d+$/.test(arg) ? Number(arg) : null
    if (arg !== '' && pinned === null) {
      return { text: `Usage: /${COMMAND} [pr-number]` }
    }

    const previous = await read($, prNumber)
    if (previous !== pinned) {
      await update($, prNumber, () => pinned)
      await update($, snapshot, () => null)
      await update($, error, () => null)
    }
    await openPane($)

    return { text: pinned === null ? 'PR review pane opened for the current branch.' : `PR review pane opened for #${pinned}.` }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const pr = await read($, snapshot)
    const problem = await read($, error)
    const loading = await read($, isLoading)
    const now = await $.clock.now()
    const width = Math.max(20, e.props.bodyColumns)

    const buttons = (
      <Box flexDirection="row" gap={1}>
        <Button key="refresh" hotkey="r" label={loading ? 'Refreshing…' : 'Refresh'} onPress={() => fetchSnapshot($)} />
        {pr !== null && pr.state === 'REVIEWING' && (
          <Button
            key="run-loop"
            hotkey="l"
            variant="primary"
            label="Run review loop"
            onPress={async () => {
              await $.prompt.submit({ text: `Run review loop for PR #${pr.number} (the pr-review-loop skill).`, asUser: true })
            }}
          />
        )}
        <Button key="close" hotkey="q" role="dismiss" label="Close" onPress={() => $.ui.close({ id: PANE })} />
      </Box>
    )

    if (pr === null) {
      return (
        <Box flexDirection="column">
          <Text dimColor={problem === null} color={problem === null ? undefined : 'red'} wrap="wrap">
            {problem ?? 'Loading the PR for this branch…'}
          </Text>
          {buttons}
        </Box>
      )
    }

    const { checks } = pr
    const copilotThreads = pr.threads.filter(t => t.isCopilot).length
    const otherThreads = pr.threads.length - copilotThreads

    return (
      <Box flexDirection="column">
        <Text bold wrap="truncate-end">
          #{pr.number} {pr.title}
          {pr.isDraft ? ' (draft)' : ''}
        </Text>
        <Text dimColor wrap="truncate-middle">
          {pr.branch} · {pr.url}
        </Text>
        <Text> </Text>
        <Text wrap="wrap">
          <Text bold color={STATE_COLOR[pr.state]}>
            {pr.state}
          </Text>{' '}
          {STATE_TEXT[pr.state]}
        </Text>
        <Text dimColor wrap="wrap">
          Copilot reviewed {formatAgo(pr.lastReviewMs, now)} · head committed {formatAgo(pr.headMs, now)}
        </Text>
        <Text wrap="wrap">
          CI: <Text color="green">✓ {checks.passed}</Text> · <Text color={checks.failed > 0 ? 'red' : undefined}>✗ {checks.failed}</Text> ·{' '}
          <Text color={checks.pending > 0 ? 'yellow' : undefined}>… {checks.pending}</Text>
          {checks.failedNames.length > 0 ? `  failing: ${checks.failedNames.join(', ')}` : ''}
        </Text>
        <Text> </Text>
        <Text bold>
          Unresolved threads: {copilotThreads} from Copilot{otherThreads > 0 ? `, ${otherThreads} from people` : ''}
        </Text>
        {pr.threads.length === 0 && <Text dimColor>None.</Text>}
        {pr.threads.map(thread => (
          <Box flexDirection="column" width={width}>
            <Text wrap="truncate-end">
              <Text color={thread.isCopilot ? 'magenta' : 'blue'}>{thread.isCopilot ? 'Copilot' : thread.author}</Text>{' '}
              <Text dimColor>{thread.location}</Text>
            </Text>
            <Text wrap="wrap">  {thread.summary}</Text>
          </Box>
        ))}
        <Text> </Text>
        <Text dimColor>
          {problem !== null ? `Last refresh failed: ${problem} · ` : ''}Updated {formatAgo(pr.fetchedAtMs, now)}
        </Text>
        {buttons}
      </Box>
    )
  })
}

import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { describeGhError, formatAgo, loopState, parseSnapshot, repoFromUrl, summarizeChecks } from '../hooks/github'

const NOW = Date.parse('2026-10-02T10:00:00Z')
const MINUTE = 60_000

const prView = (overrides: Record<string, unknown> = {}) =>
  JSON.stringify({
    number: 124,
    title: 'feat(mods): add pr-review-pane',
    url: 'https://github.com/Anras573/AIchemist/pull/124',
    headRefName: 'feat/pr-review-pane',
    headRefOid: 'abc123',
    isDraft: false,
    reviews: [
      { author: { login: 'copilot-pull-request-reviewer' }, submittedAt: '2026-10-02T09:20:00Z', commit: { oid: 'old999' } },
      { author: { login: 'copilot-pull-request-reviewer' }, submittedAt: '2026-10-02T09:50:00Z', commit: { oid: 'abc123' } },
      { author: { login: 'someone' }, submittedAt: '2026-10-02T09:55:00Z', commit: { oid: 'abc123' } },
    ],
    statusCheckRollup: [
      { __typename: 'CheckRun', name: 'lint', status: 'COMPLETED', conclusion: 'FAILURE' },
      { __typename: 'CheckRun', name: 'docs', status: 'COMPLETED', conclusion: 'SUCCESS' },
      { __typename: 'CheckRun', name: 'e2e', status: 'IN_PROGRESS', conclusion: null },
      { __typename: 'StatusContext', context: 'ci/legacy', state: 'SUCCESS' },
    ],
    ...overrides,
  })

const threads = () =>
  JSON.stringify({
    data: {
      repository: {
        pullRequest: {
          reviewThreads: {
            nodes: [
              {
                isResolved: false,
                comments: { nodes: [{ author: { login: 'copilot-pull-request-reviewer' }, body: '\nUse a `const` here.\nMore detail.', path: 'hooks/register.tsx', line: 42, url: 'https://x/1' }] },
              },
              {
                isResolved: false,
                comments: { nodes: [{ author: { login: 'alice' }, body: 'Why not a band?', path: 'docs/mods.md', line: null, url: 'https://x/2' }] },
              },
              {
                isResolved: true,
                comments: { nodes: [{ author: { login: 'copilot-pull-request-reviewer' }, body: 'Done already', path: 'a.ts', line: 1, url: 'https://x/3' }] },
              },
            ],
          },
        },
      },
    },
  })

describe('helpers', () => {
  test('reads owner and repo off the PR URL', () => {
    expect(repoFromUrl('https://github.com/Anras573/AIchemist/pull/124')).toEqual({ owner: 'Anras573', repo: 'AIchemist' })
    expect(repoFromUrl('not a url')).toBeUndefined()
  })

  test('counts check runs and status contexts', () => {
    const summary = summarizeChecks(JSON.parse(prView()).statusCheckRollup)

    expect(summary).toEqual({ passed: 2, failed: 1, pending: 1, failedNames: ['lint'] })
    expect(summarizeChecks(null)).toEqual({ passed: 0, failed: 0, pending: 0, failedNames: [] })
  })

  test('follows the pr-review-loop state machine', () => {
    expect(loopState(undefined, 'abc123', 3)).toBe('WAITING')
    expect(loopState('old999', 'abc123', 3)).toBe('WAITING')
    expect(loopState('abc123', 'abc123', 3)).toBe('REVIEWING')
    expect(loopState('abc123', 'abc123', 0)).toBe('DONE')
  })

  test('builds a snapshot of unresolved threads, Copilot first-comment summaries included', () => {
    const snap = parseSnapshot(prView(), threads(), NOW)

    expect(snap.state).toBe('REVIEWING')
    expect(snap.reviewedOid).toBe('abc123')
    expect(snap.lastReviewMs).toBe(Date.parse('2026-10-02T09:50:00Z'))
    expect(snap.threads).toEqual([
      { author: 'copilot-pull-request-reviewer', isCopilot: true, location: 'hooks/register.tsx:42', summary: 'Use a `const` here.', url: 'https://x/1' },
      { author: 'alice', isCopilot: false, location: 'docs/mods.md', summary: 'Why not a band?', url: 'https://x/2' },
    ])
  })

  test('waits when gh reports no commit for the review (an older gh)', () => {
    const reviews = [{ author: { login: 'copilot-pull-request-reviewer' }, submittedAt: '2026-10-02T09:50:00Z' }]
    const snap = parseSnapshot(prView({ reviews }), JSON.stringify({ data: { repository: { pullRequest: null } } }), NOW)

    expect(snap.reviewedOid).toBeUndefined()
    expect(snap.state).toBe('WAITING')
    expect(snap.threads).toEqual([])
  })

  test('waits when Copilot has not reviewed the latest push', () => {
    expect(parseSnapshot(prView({ headRefOid: 'def456' }), threads(), NOW).state).toBe('WAITING')
    expect(parseSnapshot(prView({ reviews: [] }), threads(), NOW).state).toBe('WAITING')
  })

  test('formats relative times', () => {
    expect(formatAgo(undefined, NOW)).toBe('never')
    expect(formatAgo(NOW - 10_000, NOW)).toBe('just now')
    expect(formatAgo(NOW - 5 * MINUTE, NOW)).toBe('5m ago')
    expect(formatAgo(NOW - 3 * 60 * MINUTE, NOW)).toBe('3h ago')
  })

  test('explains a branch without a PR', () => {
    expect(describeGhError('no pull requests found for branch "x"\n')).toMatch(/No open PR/)
    expect(describeGhError('')).toBe('gh failed with no message.')
  })
})

const ok = (stdout: string) => ({
  value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
})

// gh answered from memory: `pr view` and `api graphql`, recording each argv.
function mockGh(on: On, runs: (readonly string[])[], view = prView()) {
  on('process.run', async (_$, e) => {
    runs.push(e.argv)
    return e.argv[1] === 'pr' ? ok(view) : ok(threads())
  })
}

function mockUi(on: On) {
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('command.register', async (_$, e) => ({ value: { command: e.name } }))
  on('ui.open', async () => ({ value: { isPlaced: true, placement: 'dock' } }))
  on('ui.panes', async () => ({ value: [{ id: 'pr-review', title: 'PR review', isShown: true, isFocused: false, isPlaced: true }] }))
}

const PANE_PROPS = {
  title: 'PR review',
  isFocused: false,
  bodyColumns: 80,
  placement: 'dock',
  scroll: { offset: 0, bodyRows: 40 },
  view: {},
} as const

describe('pane', () => {
  test('the command fetches the PR and the pane draws it on every surface', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockUi(on)
    const runs: (readonly string[])[] = []
    mockGh(on, runs)

    await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
    const result = await $.command.run({ command: 'pr-pane', args: '', origin: { kind: 'composer' } } as never)
    await clock.settle()
    expect(result.text).toMatch(/current branch/)

    expect(runs[0]?.slice(0, 3)).toEqual(['gh', 'pr', 'view'])
    expect(runs[1]).toEqual(expect.arrayContaining(['api', 'graphql', 'owner=Anras573', 'repo=AIchemist', 'pr=124']))

    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ plugin: 'aichemist-pr-review-pane', surface, component: 'Pane', requestId: 'pr-review', props: PANE_PROPS } as never)
      expect(await ui.find({ text: /#124 feat\(mods\): add pr-review-pane/ })).toBeDefined()
      expect(await ui.find({ text: /REVIEWING/ })).toBeDefined()
      expect(await ui.find({ text: /on abc123 · head abc123/ })).toBeDefined()
      expect(await ui.find({ text: /Unresolved threads: 1 from Copilot, 1 from people/ })).toBeDefined()
      expect(await ui.find({ text: /failing: lint/ })).toBeDefined()
      expect(await ui.find({ key: 'run-loop' })).toBeDefined()
      await ui.unmount()
    }
  })

  test('Run review loop hands off to the skill without passing on review text', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockUi(on)
    mockGh(on, [])
    const prompts: string[] = []
    on('prompt.submit', async (_$, e) => {
      prompts.push(e.text)
      return { text: e.text }
    })

    await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
    await $.command.run({ command: 'pr-pane', args: '', origin: { kind: 'composer' } } as never)
    await clock.settle()

    const ui = await $.ui.mount({ plugin: 'aichemist-pr-review-pane', surface: 'terminal', component: 'Pane', requestId: 'pr-review', props: PANE_PROPS } as never)
    await ui.press({ key: 'run-loop' })

    expect(prompts).toEqual(['Run review loop for PR #124 (the pr-review-loop skill).'])
  })

  test('a PR number pins the pane to that PR', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockUi(on)
    const runs: (readonly string[])[] = []
    mockGh(on, runs)

    await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
    await $.command.run({ command: 'pr-pane', args: '#124', origin: { kind: 'composer' } } as never)
    await clock.settle()

    expect(runs[0]?.slice(0, 4)).toEqual(['gh', 'pr', 'view', '124'])
  })

  test('shows why when the branch has no PR', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockUi(on)
    on('process.run', async () => ({
      value: { exitCode: 1, stdout: '', stderr: 'no pull requests found for branch "main"', isStdoutTruncated: false, isStderrTruncated: false },
    }))

    await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
    await $.command.run({ command: 'pr-pane', args: '', origin: { kind: 'composer' } } as never)
    await clock.settle()

    const ui = await $.ui.mount({ plugin: 'aichemist-pr-review-pane', surface: 'terminal', component: 'Pane', requestId: 'pr-review', props: PANE_PROPS } as never)
    expect(await ui.find({ text: /No open PR for this branch/ })).toBeDefined()
    expect(await ui.find({ key: 'run-loop' })).toBeUndefined()
  })
})

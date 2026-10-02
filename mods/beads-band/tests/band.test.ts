import { describe, expect, mock, test } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'

import { bandLines, parseTasks } from '../hooks/beads'

// Shapes as bd 1.3.1 prints them (trimmed to the fields that matter).
const READY = JSON.stringify([
  { id: 'demo-0vv', title: 'Probe task', status: 'open', priority: 1, issue_type: 'task', dependency_count: 0 },
  { id: 'demo-chq', title: 'Blocker task', status: 'open', priority: 2, issue_type: 'task', dependent_count: 1 },
  { id: 'demo-zz0', title: 'Urgent fix', status: 'open', priority: 0, issue_type: 'bug' },
])
const IN_PROGRESS = JSON.stringify([
  { id: 'demo-22f', title: 'Claimed task', status: 'in_progress', priority: 2, assignee: 'unknown', started_at: '2026-10-02T08:50:56Z' },
])
const DB = '/home/me/.local/share/aichemist/beads/demo/.beads'

const task = (id: string, priority = 2, title = `Task ${id}`) => ({ id, title, priority, status: 'open' })

describe('helpers', () => {
  test('parses bd output, highest priority first, keeping bd order within a priority', () => {
    expect(parseTasks(READY).map(t => t.id)).toEqual(['demo-zz0', 'demo-0vv', 'demo-chq'])
    expect(parseTasks(IN_PROGRESS)).toEqual([{ id: 'demo-22f', title: 'Claimed task', status: 'in_progress', priority: 2 }])
  })

  test('ignores output that is not a list of issues', () => {
    expect(parseTasks('not json')).toEqual([])
    expect(parseTasks('null')).toEqual([])
    expect(parseTasks(JSON.stringify([{ title: 'no id' }, { id: 'x-1', title: 'ok' }])).map(t => t.id)).toEqual(['x-1'])
  })

  test('draws what is in progress and what is ready next', () => {
    const lines = bandLines(parseTasks(IN_PROGRESS), parseTasks(READY), 120)

    expect(lines).toEqual([
      '▶ In progress: P2 demo-22f Claimed task',
      '◇ Ready (3): P0 demo-zz0 Urgent fix · P1 demo-0vv Probe task · P2 demo-chq Blocker task',
    ])
  })

  test('never lists a task in progress as ready, and counts the rest', () => {
    const ready = [task('a'), task('b'), task('c'), task('d'), task('e')]
    const lines = bandLines([task('a'), task('b')], ready, 200)

    expect(lines[0]).toMatch(/In progress: P2 a Task a \(\+1 more\)$/)
    expect(lines[1]).toBe('◇ Ready (3): P2 c Task c · P2 d Task d · P2 e Task e')
    expect(bandLines([], [task('a'), task('b'), task('c'), task('d')], 200)[0]).toMatch(/ · \+1 more$/)
  })

  test('fits each line to the width and shows nothing when there is nothing', () => {
    const long = task('long-1', 1, 'A very long task title that keeps going well past any sensible band width')
    for (const line of bandLines([long], [long, task('x')], 40)) {
      expect(line.length).toBeLessThanOrEqual(40)
    }
    expect(bandLines([], [], 80)).toEqual([])
  })
})

const run = (exitCode: number, stdout: string) => ({
  value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
})

// The skill's script and bd, answered from memory; each argv recorded.
function mockBeads(on: On, runs: (readonly string[])[], db: string | null = DB) {
  on('process.run', async (_$, e) => {
    runs.push(e.argv)
    if (e.argv[0] === 'bash') {
      return db === null ? run(3, '') : run(0, `${db}\n`)
    }
    return run(0, e.argv.includes('ready') ? READY : IN_PROGRESS)
  })
}

function mockEngine(on: On) {
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('command.register', async (_$, e) => ({ value: { command: e.name } }))
  on('turn.complete', async (_$, e) => ({ text: e.answer }))
  // The engine's own band, drawn when the plugin passes.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e) => {
    const { Text } = $.ui.resolve(e)
    return h(Text, { key: 'engine' }, 'engine band') as RenderElement
  })
}

const BAND = {
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 6, bodyColumns: 120, scroll: { offset: 0, bodyRows: 5 }, view: {} },
} as const
const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const

describe('band', () => {
  test('shows in-progress and ready tasks on every surface, reading only', async ($, on) => {
    const clock = mock.clock(on, { now: 0 })
    mockEngine(on)
    const runs: (readonly string[])[] = []
    mockBeads(on, runs)

    await $.session.start(START)
    await clock.advance(1)

    expect(runs[0]?.[0]).toBe('bash')
    expect(runs[0]?.[1]).toMatch(/tools\/beads-db\.sh$/)
    expect(runs[0]).not.toContain('--init')
    for (const argv of runs.slice(1)) {
      expect(argv.slice(0, 4)).toEqual(['bd', '--db', DB, '--readonly'])
    }

    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ plugin: 'aichemist-beads-band', surface, ...BAND } as never)
      expect(await ui.find({ text: /In progress: P2 demo-22f Claimed task/ })).toBeDefined()
      expect(await ui.find({ text: /Ready \(3\): P0 demo-zz0 Urgent fix/ })).toBeDefined()
      await ui.unmount()
    }
  })

  test('stays out of the way when the repo has no beads database', async ($, on) => {
    const clock = mock.clock(on, { now: 0 })
    mockEngine(on)
    const runs: (readonly string[])[] = []
    mockBeads(on, runs, null)

    await $.session.start(START)
    await clock.advance(1)

    expect(runs.map(argv => argv[0])).toEqual(['bash'])
    const ui = await $.ui.mount({ plugin: 'aichemist-beads-band', surface: 'terminal', ...BAND } as never)
    expect(await ui.find({ text: /In progress|Ready/ })).toBeUndefined()
    expect(await ui.find({ text: 'engine band' })).toBeDefined()
  })

  test('Hide hides it and /beads-band brings it back', async ($, on) => {
    const clock = mock.clock(on, { now: 0 })
    mockEngine(on)
    mockBeads(on, [])

    await $.session.start(START)
    await clock.advance(1)

    const ui = await $.ui.mount({ plugin: 'aichemist-beads-band', surface: 'terminal', ...BAND } as never)
    await ui.press({ key: 'hide' })
    expect(await ui.find({ text: /In progress/ })).toBeUndefined()
    expect(await ui.find({ text: 'engine band' })).toBeDefined()

    const shown = await $.command.run({ command: 'beads-band', args: '', origin: { kind: 'composer' } } as never)
    await clock.settle()
    expect(shown.text).toMatch(/shown/)
    expect(await ui.find({ text: /In progress/ })).toBeDefined()
  })

  test('re-reads after each turn', async ($, on) => {
    const clock = mock.clock(on, { now: 0 })
    mockEngine(on)
    const runs: (readonly string[])[] = []
    mockBeads(on, runs)

    await $.session.start(START)
    await clock.advance(1)
    const before = runs.length

    await $.turn.complete({ answer: 'done', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.settle()

    expect(runs.length).toBe(before * 2)
  })

  test('does nothing in a non-interactive session', async ($, on) => {
    const clock = mock.clock(on, { now: 0 })
    mockEngine(on)
    const runs: (readonly string[])[] = []
    mockBeads(on, runs)

    await $.session.start({ ...START, surface: null, isInteractive: false })
    await clock.advance(120_000)

    expect(runs).toEqual([])
  })
})

import { describe, expect, mock, test } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'

import { bandLines, parseChangedFiles, parseCsvLine, parseFindings } from '../hooks/lizard'

// Rows as lizard 1.26 prints them with --csv (no header).
const CSV = [
  '12,18,120,2,30,"processOrder@42-71@src/OrderService.ts","src/OrderService.ts","processOrder","processOrder( a , b )",42,71',
  '5,3,40,1,6,"tiny@1-6@src/util.ts","src/util.ts","tiny","tiny( x )",1,6',
  '30,21,300,0,60,"apply@5-64@src/Discounts.ts","src/Discounts.ts","apply","apply( )",5,64',
  '9,15,90,1,9,"edge@1-9@src/edge.ts","src/edge.ts","edge","edge( )",1,9',
].join('\n')

// `git status --porcelain=v1 -z`: modified, untracked, renamed (+ original), deleted.
const STATUS = [' M src/OrderService.ts', '?? src/new file.ts', 'R  src/b.ts', 'src/a.ts', ' D src/gone.ts', 'A  src/added.ts'].join('\0') + '\0'

describe('helpers', () => {
  test('lists changed files that still exist, using a rename’s new path', () => {
    expect(parseChangedFiles(STATUS)).toEqual(['src/OrderService.ts', 'src/new file.ts', 'src/b.ts', 'src/added.ts'])
    expect(parseChangedFiles('')).toEqual([])
  })

  test('splits CSV lines, honouring quoted commas', () => {
    expect(parseCsvLine('1,"a, b","say ""hi""",x')).toEqual(['1', 'a, b', 'say "hi"', 'x'])
  })

  test('keeps functions above the threshold, most complex first', () => {
    expect(parseFindings(CSV, 15).map(f => [f.name, f.ccn, f.line])).toEqual([
      ['apply', 21, 5],
      ['processOrder', 18, 42],
    ])
    expect(parseFindings(CSV, 25)).toEqual([])
  })

  test('ignores lines that are not lizard rows', () => {
    expect(parseFindings('warning: something\n\n1,2', 1)).toEqual([])
  })

  test('draws a headline with the worst functions and a count of the rest', () => {
    const findings = parseFindings(CSV, 15)
    expect(bandLines(findings, 15, 200)).toEqual([
      '🔥 Complexity > 15 in changed files (2): apply CCN 21 src/Discounts.ts:5 · processOrder CCN 18 src/OrderService.ts:42',
      'Run /hotspot to weigh these against git churn',
    ])

    const many = Array.from({ length: 5 }, (_, i) => ({ file: 'f.ts', name: `fn${i}`, ccn: 20 - i, line: i }))
    expect(bandLines(many, 15, 300)[0]).toMatch(/ · \+2 more$/)
  })

  test('fits each line to the width and shows nothing when nothing is flagged', () => {
    for (const line of bandLines(parseFindings(CSV, 15), 15, 40)) {
      expect(line.length).toBeLessThanOrEqual(40)
    }
    expect(bandLines([], 15, 80)).toEqual([])
  })
})

const run = (exitCode: number, stdout: string) => ({
  value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
})

// git and lizard, answered from memory; each argv recorded.
function mockTools(on: On, runs: (readonly string[])[], opts: { lizard?: boolean; repo?: boolean } = {}) {
  on('process.run', async (_$, e) => {
    runs.push(e.argv)
    if (e.argv[1] === 'rev-parse') {
      return opts.repo === false ? run(128, '') : run(0, '/repo\n')
    }
    if (e.argv[0] === 'git') {
      return run(0, STATUS)
    }
    return opts.lizard === false ? run(127, '') : run(0, CSV)
  })
}

function mockEngine(on: On) {
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('command.register', async (_$, e) => ({ value: { command: e.name } }))
  on('turn.complete', async (_$, e) => ({ text: e.answer }))
  on('ui.render', { component: 'AbovePrompt' }, async ($, e) => {
    const { Text } = $.ui.resolve(e)
    return h(Text, { key: 'engine' }, 'engine band') as RenderElement
  })
}

const BAND = {
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 6, bodyColumns: 160, scroll: { offset: 0, bodyRows: 5 }, view: {} },
} as const
const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const

describe('band', () => {
  test('flags complex changed functions, passing paths after -- to lizard', async ($, on) => {
    const clock = mock.clock(on, { now: 0 })
    mockEngine(on)
    const runs: (readonly string[])[] = []
    mockTools(on, runs)

    await $.session.start(START)
    await clock.advance(1)

    const lizard = runs.find(argv => argv[0] === 'lizard')
    expect(lizard?.slice(0, 3)).toEqual(['lizard', '--csv', '--'])
    expect(lizard).toContain('src/new file.ts')
    expect(runs.every(argv => argv[0] === 'git' || argv[0] === 'lizard')).toBe(true)

    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ plugin: 'aichemist-lizard-band', surface, ...BAND } as never)
      expect(await ui.find({ text: /Complexity > 15 in changed files \(2\): apply CCN 21/ })).toBeDefined()
      await ui.unmount()
    }
  })

  test('steps aside when lizard is missing or this is not a git repo', async ($, on) => {
    const clock = mock.clock(on, { now: 0 })
    mockEngine(on)
    mockTools(on, [], { lizard: false })

    await $.session.start(START)
    await clock.advance(1)

    const ui = await $.ui.mount({ plugin: 'aichemist-lizard-band', surface: 'terminal', ...BAND } as never)
    expect(await ui.find({ text: /Complexity/ })).toBeUndefined()
    expect(await ui.find({ text: 'engine band' })).toBeDefined()
  })

  test('Hide hides it and /lizard-band brings it back', async ($, on) => {
    const clock = mock.clock(on, { now: 0 })
    mockEngine(on)
    mockTools(on, [])

    await $.session.start(START)
    await clock.advance(1)

    const ui = await $.ui.mount({ plugin: 'aichemist-lizard-band', surface: 'terminal', ...BAND } as never)
    await ui.press({ key: 'hide' })
    expect(await ui.find({ text: /Complexity/ })).toBeUndefined()

    const shown = await $.command.run({ command: 'lizard-band', args: '', origin: { kind: 'composer' } } as never)
    await clock.settle()
    expect(shown.text).toMatch(/shown/)
    expect(await ui.find({ text: /Complexity/ })).toBeDefined()
  })

  test('scans again after each turn', async ($, on) => {
    const clock = mock.clock(on, { now: 0 })
    mockEngine(on)
    const runs: (readonly string[])[] = []
    mockTools(on, runs)

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
    mockTools(on, runs)

    await $.session.start({ ...START, surface: null, isInteractive: false })
    await clock.advance(120_000)

    expect(runs).toEqual([])
  })
})

import { describe, expect, mock, test } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'

import {
  age,
  bandLines,
  cksum,
  claudeConfigDir,
  deliveryPath,
  findRememberRoot,
  gitBashFromExecPath,
  handoffPath,
  isWindowsPath,
  parseDelivery,
  parseDoctor,
  parseNext,
  utf8,
} from '../hooks/remember'

const HOME = '/home/me'
const ROOT = '/home/me/proj'
const PLUGIN = '/home/me/.claude/plugins/cache/dpt-plugins/remember/0.43.1'
const STORE = '/home/me/.remember/-home-me-proj'
const SESSION = 'sess-1'
const HOUR = 3_600_000
const NOW = 1_800_000_000_000

// The format the /remember skill writes.
const NOTE = `# Handoff

## State
Band mod drafted on branch \`feat/remember-band\`; tests green.

## Next
1. Open the PR for **remember-band**
2. Run \`claude plugin validate .\`
3. [x] Write the docs entry
4. Ask about the hotkey

## Context
Remember's doctor --json is provisional.
`

const INSTALLED = JSON.stringify({
  version: 2,
  plugins: {
    'beads@x': [{ scope: 'user', installPath: '/elsewhere' }],
    'remember@dpt-plugins': [{ scope: 'user', installPath: PLUGIN, version: '0.43.1' }],
  },
})
const DOCTOR = JSON.stringify({
  schema_version: 1,
  state: 'resolved',
  remember_dir: STORE,
  storage_mode: 'external',
  project_dir: ROOT,
})

describe('helpers', () => {
  test('finds Remember in installed_plugins.json, preferring this project', () => {
    expect(findRememberRoot(INSTALLED, ROOT)).toBe(PLUGIN)
    const both = JSON.stringify({
      version: 2,
      plugins: {
        'remember@claude-plugins-official': [
          { scope: 'project', installPath: '/other', projectPath: '/somewhere/else' },
          { scope: 'user', installPath: '/user' },
          { scope: 'project', installPath: '/mine', projectPath: ROOT },
        ],
      },
    })
    expect(findRememberRoot(both, ROOT)).toBe('/mine')
    expect(findRememberRoot(both, '/x')).toBe('/user')
    expect(findRememberRoot(JSON.stringify({ plugins: { 'remember@m': { installPath: '/v1' } } }), ROOT)).toBe('/v1')
    expect(findRememberRoot(JSON.stringify({ plugins: { 'remembered@m': [{ installPath: '/no' }] } }), ROOT)).toBeNull()
    expect(findRememberRoot('not json', ROOT)).toBeNull()
  })

  test('reads doctor --json only at schema version 1 and when resolved', () => {
    expect(parseDoctor(`${DOCTOR}\n`)).toEqual({ dir: STORE, isInProject: false })
    expect(parseDoctor(JSON.stringify({ schema_version: 1, state: 'resolved_assumed_project_dir', remember_dir: `${ROOT}/.remember/`, storage_mode: 'legacy' })))
      .toEqual({ dir: `${ROOT}/.remember`, isInProject: true })
    expect(parseDoctor(JSON.stringify({ schema_version: 2, state: 'resolved', remember_dir: STORE }))).toBeNull()
    expect(parseDoctor(JSON.stringify({ schema_version: 1, state: 'could_not_resolve', reason: 'x' }))).toBeNull()
    expect(parseDoctor('OK   human report')).toBeNull()
  })

  test('trusts the handoff hint only inside the store', () => {
    expect(handoffPath(`${STORE}/remember.${SESSION}.md\n`, STORE)).toBe(`${STORE}/remember.${SESSION}.md`)
    expect(handoffPath(null, STORE)).toBe(`${STORE}/remember.md`)
    expect(handoffPath('/etc/passwd', STORE)).toBe(`${STORE}/remember.md`)
    expect(handoffPath(`${STORE}/notes.md`, STORE)).toBe(`${STORE}/remember.md`)
    expect(handoffPath(`${STORE}/sub/remember.md`, STORE)).toBe(`${STORE}/remember.md`)
  })

  test('pairs each handoff with its delivery record', () => {
    expect(deliveryPath(`${STORE}/remember.md`, STORE)).toBe(`${STORE}/tmp/remember.delivered`)
    expect(deliveryPath(`${STORE}/remember.${SESSION}.md`, STORE)).toBe(`${STORE}/tmp/remember.delivered.${SESSION}`)
  })

  test('parses the delivery record', () => {
    expect(parseDelivery('fingerprint=123-456\nfirst_delivered=2026-11-08 09:12\ndeliveries=4\n')).toEqual({
      fingerprint: '123-456',
      firstDelivered: '2026-11-08 09:12',
      deliveries: 4,
    })
    expect(parseDelivery('deliveries=oops').deliveries).toBe(0)
  })

  test('fingerprints like POSIX cksum, without running it', () => {
    // Expected values from `printf … | cksum`.
    expect(cksum(utf8('hello\n'))).toBe('3015617425-6')
    expect(cksum(utf8(''))).toBe('4294967295-0')
    expect(cksum(utf8('Ærø → ✓\n'))).toBe('184757777-14')
  })

  test('finds the config folder and Git Bash on Windows', () => {
    expect(claudeConfigDir({ configDir: '/cfg', home: HOME })).toBe('/cfg')
    expect(claudeConfigDir({ home: HOME, userProfile: 'C:\\Users\\me' })).toBe(`${HOME}/.claude`)
    expect(claudeConfigDir({ userProfile: 'C:\\Users\\me' })).toBe('C:\\Users\\me/.claude')
    expect(claudeConfigDir({})).toBeNull()
    expect([isWindowsPath('E:\\proj'), isWindowsPath('c:/proj'), isWindowsPath('/home/me')]).toEqual([true, true, false])
    expect(gitBashFromExecPath('C:/Program Files/Git/ucrt64/libexec/git-core\n')).toBe('C:/Program Files/Git/bin/bash.exe')
    expect(gitBashFromExecPath('C:\\Git\\mingw64\\libexec\\git-core')).toBe('C:/Git/bin/bash.exe')
    expect(gitBashFromExecPath('/usr/lib/git-core')).toBeNull()
  })

  test('takes the open items under ## Next, skipping checked ones', () => {
    expect(parseNext(NOTE)).toEqual([
      'Open the PR for remember-band',
      'Run claude plugin validate .',
      'Ask about the hotkey',
    ])
    expect(parseNext('# Handoff\n\n## Next\n- a\n  - nested detail\n- b\n')).toEqual(['a', 'b'])
    expect(parseNext('# Handoff\n## Next\nPick up the flaky test.\n## Context\nx')).toEqual(['Pick up the flaky test.'])
    expect(parseNext('No active work.')).toEqual([])
    expect(parseNext('# Handoff\n## Next\nNo active work.\n')).toEqual([])
  })

  test('draws the items and a note when the handoff was already loaded', () => {
    const lines = bandLines(
      { next: ['A', 'B', 'C', 'D'], writtenMs: NOW - 3 * HOUR, redelivered: { count: 4, since: '2026-11-08 09:12' } },
      120,
      NOW,
    )
    expect(lines).toEqual([
      '↪ Next (4, handoff 3h ago): A · B · C · +1 more',
      '⚠ Same handoff loaded 4× since 2026-11-08 09:12. /remember writes a new one',
    ])
    const long = 'A very long open item that keeps going well past any sensible band width at all'
    for (const line of bandLines({ next: [long, long], writtenMs: NOW, redelivered: { count: 2, since: '' } }, 40, NOW)) {
      expect(line.length).toBeLessThanOrEqual(40)
    }
    expect(bandLines({ next: [], writtenMs: NOW, redelivered: null }, 80, NOW)).toEqual([])
    expect([age(NOW, NOW), age(NOW - 5 * 60_000, NOW), age(NOW - 50 * HOUR, NOW)]).toEqual(['just now', '5m ago', '2d ago'])
  })
})

type Files = Record<string, string>
type Options = {
  files?: Files
  links?: string[]
  doctor?: string
  tracked?: boolean
  root?: string
  env?: Record<string, string>
  gitExecPath?: string
}

const run = (exitCode: number, stdout: string) => ({
  value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
})

const baseFiles = (): Files => ({
  [`${HOME}/.claude/plugins/installed_plugins.json`]: INSTALLED,
  [`${PLUGIN}/scripts/doctor.sh`]: '#!/bin/bash',
  [`${STORE}/tmp/handoff-path`]: `${STORE}/remember.md\n`,
  [`${STORE}/remember.md`]: NOTE,
})

// Claude Code's file system, env and processes, answered from memory; every
// process argv and every write recorded.
function mockHost(on: On, opts: Options = {}) {
  const files = opts.files ?? baseFiles()
  const runs: { argv: readonly string[]; env?: Record<string, string> }[] = []
  const writes: string[] = []

  const env = opts.env ?? { HOME }
  // The kit hands fs paths over resolved for the OS it runs on: on Windows,
  // `/home/me/x` arrives as `E:\home\me\x`. Match on a drive- and
  // separator-free spelling so the same fixtures work everywhere.
  const canon = (path: string) => path.replace(/^[A-Za-z]:/, '').replace(/\\/g, '/')
  const lookup = (path: string) => Object.keys(files).find(key => canon(key) === canon(path))
  const isLink = (path: string) => (opts.links ?? []).some(link => canon(link) === canon(path))

  on('session.root', async () => ({ value: opts.root ?? ROOT }))
  on('session.id', async () => ({ value: SESSION }))
  on('env.get', async (_$, e) => ({ value: env[e.name] }))
  on('fs.read', async (_$, e) => {
    const key = lookup(e.path)
    return key === undefined ? { deny: `ENOENT: ${e.path}` } : { value: files[key]! }
  })
  on('fs.exists', async (_$, e) => ({ value: lookup(e.path) !== undefined }))
  on('fs.stat', async (_$, e) => {
    const key = lookup(e.path)
    return key === undefined
      ? { deny: `ENOENT: ${e.path}` }
      : { value: { kind: 'file', size: files[key]!.length, mtimeMs: NOW - 2 * HOUR, isLink: isLink(e.path) } }
  })
  on('fs.write', async (_$, e) => {
    writes.push(e.path)
    return { value: undefined }
  })
  on('process.run', async (_$, e) => {
    runs.push({ argv: e.argv, env: e.init?.env })
    if (/(^|\/)bash(\.exe)?$/.test(e.argv[0]!)) {
      return run(0, `${opts.doctor ?? DOCTOR}\n`)
    }
    if (e.argv[0] === 'git' && e.argv[1] === '--exec-path') {
      return opts.gitExecPath ? run(0, `${opts.gitExecPath}\n`) : run(127, '')
    }
    if (e.argv[0] === 'git') {
      return run(opts.tracked ? 0 : 1, '')
    }
    return run(127, '')
  })

  return { runs, writes, files }
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
  props: { hasSurvey: false, isWorking: false, maxRows: 6, bodyColumns: 120, scroll: { offset: 0, bodyRows: 5 }, view: {} },
} as const
const START = { cwd: ROOT, surface: 'terminal', isInteractive: true } as const

async function start(
  $: { session: { start: (e: typeof START) => Promise<unknown> } },
  clock: { advance: (ms: number) => Promise<unknown> },
) {
  await $.session.start(START)
  await clock.advance(2000)
}

describe('band', () => {
  test('shows the open items on every surface, reading only', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockEngine(on)
    const host = mockHost(on)

    await start($, clock)

    const doctor = host.runs.find(r => r.argv[0] === 'bash')
    expect(doctor?.argv).toEqual(['bash', `${PLUGIN}/scripts/doctor.sh`, '--json'])
    expect(doctor?.env).toEqual({ CLAUDE_PROJECT_DIR: ROOT, CLAUDE_CODE_SESSION_ID: SESSION })
    expect(host.writes).toEqual([])

    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ plugin: 'aichemist-remember-band', surface, ...BAND } as never)
      expect(await ui.find({ text: /Next \(3, handoff 2h ago\): Open the PR for remember-band · Run claude plugin validate \./ })).toBeDefined()
      expect(await ui.find({ text: /Same handoff loaded/ })).toBeUndefined()
      await ui.unmount()
    }
  })

  test('asks doctor once, then only re-reads the files', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockEngine(on)
    const host = mockHost(on)

    await start($, clock)
    await $.turn.complete({ answer: 'done', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.settle()
    await clock.advance(60_000)

    expect(host.runs.filter(r => r.argv[0] === 'bash')).toHaveLength(1)
  })

  test('reads this session\'s own handoff in per-session mode, and says when it is stale', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockEngine(on)
    const files = baseFiles()
    files[`${STORE}/tmp/handoff-path.${SESSION}`] = `${STORE}/remember.${SESSION}.md`
    const mine = '# Handoff\n## Next\n- Only mine\n'
    files[`${STORE}/remember.${SESSION}.md`] = mine
    files[`${STORE}/tmp/remember.delivered.${SESSION}`] = `fingerprint=${cksum(utf8(mine))}\nfirst_delivered=2026-11-08 09:12\ndeliveries=3\n`
    mockHost(on, { files })

    await start($, clock)

    const ui = await $.ui.mount({ plugin: 'aichemist-remember-band', surface: 'terminal', ...BAND } as never)
    expect(await ui.find({ text: /Next \(1, handoff 2h ago\): Only mine/ })).toBeDefined()
    expect(await ui.find({ text: /Same handoff loaded 3× since 2026-11-08 09:12/ })).toBeDefined()
  })

  test('drops the stale note once /remember has written a different handoff', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockEngine(on)
    const files = baseFiles()
    files[`${STORE}/tmp/remember.delivered`] = 'fingerprint=999-1\nfirst_delivered=2026-11-08 09:12\ndeliveries=5\n'
    mockHost(on, { files })

    await start($, clock)

    const ui = await $.ui.mount({ plugin: 'aichemist-remember-band', surface: 'terminal', ...BAND } as never)
    expect(await ui.find({ text: /Next \(3/ })).toBeDefined()
    expect(await ui.find({ text: /Same handoff loaded/ })).toBeUndefined()
  })

  for (const [name, opts] of [
    ['Remember is not installed', { files: { [`${HOME}/.claude/plugins/installed_plugins.json`]: '{"version":2,"plugins":{}}' } }],
    ['doctor speaks a newer schema', { doctor: JSON.stringify({ schema_version: 2, state: 'resolved', remember_dir: STORE }) }],
    ['there is no handoff yet', { files: (() => { const f = baseFiles(); delete f[`${STORE}/remember.md`]; return f })() }],
    ['the handoff is a symlink', { links: [`${STORE}/remember.md`] }],
    ['the handoff has no open items', { files: { ...baseFiles(), [`${STORE}/remember.md`]: 'No active work.\n' } }],
  ] as [string, Options][]) {
    test(`stays out of the way when ${name}`, async ($, on) => {
      const clock = mock.clock(on, { now: NOW })
      mockEngine(on)
      mockHost(on, opts)

      await start($, clock)

      const ui = await $.ui.mount({ plugin: 'aichemist-remember-band', surface: 'terminal', ...BAND } as never)
      expect(await ui.find({ text: /Next/ })).toBeUndefined()
      expect(await ui.find({ text: 'engine band' })).toBeDefined()
    })
  }

  test('on Windows, finds Remember without HOME and runs its doctor with Git Bash', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockEngine(on)
    const root = 'E:\\proj'
    const plugin = 'C:\\Users\\me\\.claude\\plugins\\cache\\claude-plugins-official\\remember\\0.43.1'
    const dir = 'E:\\proj/.remember'
    const host = mockHost(on, {
      root,
      env: { USERPROFILE: 'C:\\Users\\me' },
      gitExecPath: 'C:/Program Files/Git/ucrt64/libexec/git-core',
      doctor: JSON.stringify({ schema_version: 1, state: 'resolved', remember_dir: dir, storage_mode: 'legacy' }),
      files: {
        'C:\\Users\\me/.claude/plugins/installed_plugins.json': JSON.stringify({
          version: 2,
          plugins: { 'remember@claude-plugins-official': [{ scope: 'user', installPath: plugin }] },
        }),
        [`${plugin}/scripts/doctor.sh`]: '',
        'C:/Program Files/Git/bin/bash.exe': '',
        [`${dir}/tmp/handoff-path`]: `${dir}/remember.md\n`,
        [`${dir}/remember.md`]: NOTE,
        [`${dir}/tmp/remember.delivered`]: `fingerprint=${cksum(utf8(NOTE))}\nfirst_delivered=2026-11-11 12:08\ndeliveries=2\n`,
      },
    })

    await start($, clock)

    expect(host.runs.find(r => r.argv[0]!.endsWith('bash.exe'))?.argv).toEqual([
      'C:/Program Files/Git/bin/bash.exe',
      'C:/Users/me/.claude/plugins/cache/claude-plugins-official/remember/0.43.1/scripts/doctor.sh',
      '--json',
    ])
    expect(host.runs.some(r => r.argv[0] === 'bash' || r.argv[0] === 'cksum')).toBe(false)
    const ui = await $.ui.mount({ plugin: 'aichemist-remember-band', surface: 'terminal', ...BAND } as never)
    expect(await ui.find({ text: /Next \(3/ })).toBeDefined()
    expect(await ui.find({ text: /Same handoff loaded 2× since 2026-11-11 12:08/ })).toBeDefined()
  })

  test('on Windows, stays out of the way rather than use WSL bash', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockEngine(on)
    const plugin = 'C:\\Users\\me\\remember'
    const host = mockHost(on, {
      root: 'E:\\proj',
      env: { USERPROFILE: 'C:\\Users\\me' },
      files: {
        'C:\\Users\\me/.claude/plugins/installed_plugins.json': JSON.stringify({
          plugins: { 'remember@x': [{ installPath: plugin }] },
        }),
        [`${plugin}/scripts/doctor.sh`]: '',
      },
    })

    await start($, clock)

    expect(host.runs.some(r => /bash/.test(r.argv[0]!))).toBe(false)
    const ui = await $.ui.mount({ plugin: 'aichemist-remember-band', surface: 'terminal', ...BAND } as never)
    expect(await ui.find({ text: /Next/ })).toBeUndefined()
  })

  test('refuses an in-project handoff that git tracks', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockEngine(on)
    const dir = `${ROOT}/.remember`
    const host = mockHost(on, {
      tracked: true,
      doctor: JSON.stringify({ schema_version: 1, state: 'resolved', remember_dir: dir, storage_mode: 'legacy' }),
      files: {
        [`${HOME}/.claude/plugins/installed_plugins.json`]: INSTALLED,
        [`${PLUGIN}/scripts/doctor.sh`]: '',
        [`${dir}/remember.md`]: NOTE,
      },
    })

    await start($, clock)

    expect(host.runs.find(r => r.argv[0] === 'git')?.argv).toEqual(['git', '-C', dir, 'ls-files', '--error-unmatch', '--', `${dir}/remember.md`])
    const ui = await $.ui.mount({ plugin: 'aichemist-remember-band', surface: 'terminal', ...BAND } as never)
    expect(await ui.find({ text: /Next/ })).toBeUndefined()
  })

  test('Hide hides it and /remember-band brings it back', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockEngine(on)
    mockHost(on)

    await start($, clock)

    const ui = await $.ui.mount({ plugin: 'aichemist-remember-band', surface: 'terminal', ...BAND } as never)
    await ui.press({ key: 'hide' })
    expect(await ui.find({ text: /Next/ })).toBeUndefined()
    expect(await ui.find({ text: 'engine band' })).toBeDefined()

    const shown = await $.command.run({ command: 'remember-band', args: '', origin: { kind: 'composer' } } as never)
    await clock.settle()
    expect(shown.text).toMatch(/shown/)
    expect(await ui.find({ text: /Next/ })).toBeDefined()
  })

  test('picks up a handoff /remember writes during a turn', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockEngine(on)
    const host = mockHost(on)

    await start($, clock)
    host.files[`${STORE}/remember.md`] = '# Handoff\n## Next\n- Fresh item\n'
    await $.turn.complete({ answer: 'done', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.settle()

    const ui = await $.ui.mount({ plugin: 'aichemist-remember-band', surface: 'terminal', ...BAND } as never)
    expect(await ui.find({ text: /Next \(1, handoff 2h ago\): Fresh item/ })).toBeDefined()
  })

  test('does nothing in a non-interactive session', async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    mockEngine(on)
    const host = mockHost(on)

    await $.session.start({ ...START, surface: null, isInteractive: false })
    await clock.advance(120_000)

    expect(host.runs).toEqual([])
  })
})

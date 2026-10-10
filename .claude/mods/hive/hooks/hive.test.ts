import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'


// A fake machine the probes look at: which tunnel env files exist, kube's answer, which ports answer.
type Machine = {
  files: Record<string, string>
  kube: string | null
  open: number[]
  ps: string
  kubectlThrows?: boolean
}
const ran = (exitCode: number, stdout: string) => ({ exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false })
const machine = (m: Partial<Machine> = {}): Machine => ({ files: {}, kube: 'development-primary', open: [], ps: '', ...m })

// The world beneath the mod: each `$` call it makes needs an answer in a test.
// `set` records what the mod pins into the process environment.
const world = (on: On, set: Record<string, string | undefined> = {}, m: Machine = machine()) => {
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('env.set', (_$, e) => { set[e.name] = e.value; return { value: undefined } })
  on('ui.invalidate', () => ({ value: undefined }))
  on('fs.list', (_$, e) => ({
    value: Object.keys(m.files).filter(f => f.startsWith(e.path + '/')).map(f => ({ name: f.slice(e.path.length + 1), kind: 'file' as const })) as never,
  }))
  on('fs.read', (_$, e) => (e.path in m.files ? { value: m.files[e.path] ?? '' } : { deny: 'ENOENT ' + e.path }))
  on('prompt.context', (_$, e) => ({ blocks: e.blocks }))
  on('process.run', (_$, e) => {
    const [cmd, ...rest] = e.argv
    if (cmd === 'kubectl') {
      if (m.kubectlThrows) return { deny: 'spawn kubectl ENOENT' }
      return { value: ran(m.kube === null ? 1 : 0, (m.kube ?? '') + '\n') }
    }
    if (cmd === 'bash') {
      const port = Number(/\/(\d+)$/.exec(rest[1] ?? '')?.[1])
      return { value: ran(m.open.includes(port) ? 0 : 1, '') }
    }
    if (cmd === 'ps') return { value: ran(0, m.ps) }
    return { deny: 'unexpected ' + cmd }
  })
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('audio.play', () => ({ value: undefined }))
  on('tool.call', () => ({ result: 'ok', text: 'ok', isError: false }) as never)
  // The engine's own footer: the mode labels as text, so a rewrite of `modes` is visible.
  on('ui.render', (_$, e) => h('Text', null, String(((e.props as { modes?: readonly string[] }).modes ?? []).join(' & '))) as never)
}

const START = { cwd: '/tmp', surface: 'terminal', isInteractive: true } as const

test('plain session: apiaryOs tools refused, no band, no mode label', async ($, on) => {
  world(on)
  mock.env(on, { APIARY_CAPTURE_DISABLED: '1' })
  await $.session.start(START)

  const ran = await $.tool.call({ tool: 'mcp__apiaryos__brand_list' } as never)
  expect(String(ran.deny)).toMatch(/hive: apiaryOs is off/)

  const mode = await $.ui.mount({ plugin: 'hive', surface: 'terminal', component: 'SessionMode', props: { modes: ['focus'] } })
  expect(await mode.find({ type: 'Text', text: /HIVE/ })).toBeUndefined()
  await mode.unmount()
})

test('unset kill switch: plain, and the mod pins APIARY_CAPTURE_DISABLED=1 for child hooks', async ($, on) => {
  const set: Record<string, string | undefined> = {}
  world(on, set)
  on('env.get', () => ({ value: undefined }))
  await $.session.start(START)

  const ran = await $.tool.call({ tool: 'mcp__apiaryos__brand_list' } as never)
  expect(String(ran.deny)).toMatch(/hive: apiaryOs is off/)
  expect(set.APIARY_CAPTURE_DISABLED).toBe('1')
})

test('hive session never touches the kill switch', async ($, on) => {
  const set: Record<string, string | undefined> = {}
  world(on, set)
  mock.env(on, { APIARY_CAPTURE_DISABLED: '0' })
  await $.session.start(START)
  expect(set.APIARY_CAPTURE_DISABLED).toBeUndefined()
})

test('hive session: tools pass the guard, band and mode label drawn', async ($, on) => {
  world(on)
  mock.env(on, { APIARY_CAPTURE_DISABLED: '0' })
  await $.session.start(START)

  const ran = await $.tool.call({ tool: 'mcp__apiaryos__brand_list' } as never)
  expect(ran.deny).toBeUndefined()
  expect(ran.text).toBe('ok')

  const mode = await $.ui.mount({ plugin: 'hive', surface: 'terminal', component: 'SessionMode', props: { modes: ['focus'] } })
  expect(await mode.find({ type: 'Text', text: /HIVE/ })).toBeDefined()
  await mode.unmount()

  const band = await $.ui.mount({
    plugin: 'hive', surface: 'terminal', component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false, bodyColumns: 80, bodyRows: 4, maxRows: 5 } as never,
  })
  expect(await band.find({ type: 'Text', text: /apiaryOs LIVE/ })).toBeDefined()
  await band.unmount()
})


// ---- environment tint (PLAN.md § E) -----------------------------------------------------------

const BAND = { hasSurvey: false, isWorking: false, bodyColumns: 120, bodyRows: 4, maxRows: 5 } as never
const PROD_TUNNEL = { '/tmp/implentio-db-production.env': 'PORT=51003\nUSERNAME=u\nPASSWORD=hunter2\nPG_TUNNEL_URL=x\n' }

test('prod tunnel + prod kube: red PROD row, context block says production, password never leaks', async ($, on) => {
  world(on, {}, machine({ files: PROD_TUNNEL, kube: 'production-primary', open: [40080, 9001], ps: 'kubectl port-forward -n production svc/api 9001:9001\n' }))
  mock.env(on, { APIARY_CAPTURE_DISABLED: '1' })
  mock.clock(on)
  await $.session.start(START)

  const band = await $.ui.mount({ plugin: 'hive', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  expect(await band.find({ type: 'Text', text: /PROD · DB production :51003 · kube production-primary · trino :40080 ✓ · api :9001 ✓ → prod/ })).toBeDefined()
  await band.unmount()

  const ctx = await $.prompt.context({ blocks: [] })
  const block = ctx.blocks.find(b => b.name === 'hive-env')
  expect(block).toBeDefined()
  expect(block?.text).toMatch(/PRODUCTION/)
  expect(block?.text).toMatch(/DB tunnel: production :51003/)
  expect(block?.text).not.toMatch(/hunter2/)
})

test('no tunnel, dev kube, nothing listening: green dev row, context says development only', async ($, on) => {
  world(on, {}, machine({ kube: 'development-primary' }))
  mock.env(on, { APIARY_CAPTURE_DISABLED: '1' })
  mock.clock(on)
  await $.session.start(START)

  const band = await $.ui.mount({ plugin: 'hive', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  expect(await band.find({ type: 'Text', text: /● dev · DB no tunnel · kube development-primary · trino :40080 ✗ · api :9001 ✗/ })).toBeDefined()
  await band.unmount()

  const ctx = await $.prompt.context({ blocks: [] })
  const text = ctx.blocks.find(b => b.name === 'hive-env')?.text
  expect(text).toMatch(/DEVELOPMENT only/)
  expect(text).toMatch(/DB tunnel: none$/m)
})

test('kubectl missing: row shows kube ?, session still starts, /env answers', async ($, on) => {
  world(on, {}, machine({ kubectlThrows: true }))
  mock.env(on, { APIARY_CAPTURE_DISABLED: '1' })
  mock.clock(on)
  await $.session.start(START)

  const band = await $.ui.mount({ plugin: 'hive', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  expect(await band.find({ type: 'Text', text: /○ local · DB no tunnel · kube \?/ })).toBeDefined()
  await band.unmount()

  const out = await $.command.run({ command: 'env' } as never)
  expect(String((out as { text?: string }).text)).toMatch(/verdict: none[\s\S]*kube context: \?/)
})

test('poll: a tunnel opened after start shows up within one tick', async ($, on) => {
  const m = machine({ kube: 'development-primary' })
  world(on, {}, m)
  mock.env(on, { APIARY_CAPTURE_DISABLED: '1' })
  const clock = mock.clock(on)
  await $.session.start(START)

  m.files['/tmp/implentio-db-production.env'] = 'PORT=51007\n'
  await clock.advance(15000)

  const band = await $.ui.mount({ plugin: 'hive', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  expect(await band.find({ type: 'Text', text: /PROD · DB production :51007/ })).toBeDefined()
  await band.unmount()
})

test('hive session: amber row and env row both drawn', async ($, on) => {
  world(on, {}, machine({ kube: 'development-primary' }))
  mock.env(on, { APIARY_CAPTURE_DISABLED: '0' })
  mock.clock(on)
  await $.session.start(START)

  const band = await $.ui.mount({ plugin: 'hive', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  expect(await band.find({ type: 'Text', text: /apiaryOs LIVE/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /● dev · DB no tunnel/ })).toBeDefined()
  await band.unmount()
})

import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'


// The world beneath the mod: each `$` call it makes needs an answer in a test.
// `set` records what the mod pins into the process environment.
const world = (on: On, set: Record<string, string | undefined> = {}) => {
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('env.set', (_$, e) => { set[e.name] = e.value; return { value: undefined } })
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


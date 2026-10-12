import type { On, TurnStepInput, TurnUsage } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

const MIN = 60_000

type World = { status: (string | undefined)[]; toasts: string[] }

// The engine beneath the mod: the bottom of every chain the mod's hooks stand on.
const world = (on: On, usage: () => TurnUsage | null): World => {
  const w: World = { status: [], toasts: [] }
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('session.end', (_$, e) => ({ sessionId: e.sessionId }))
  on('session.compact', (_$, e) => ({ messages: e.messages }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('ui.status', (_$, e) => { w.status.push(e.text); return { value: undefined } })
  on('ui.toast', (_$, e) => { w.toasts.push(e.text); return { value: undefined } })
  // The engine's own empty band, drawn when the mod has nothing to show.
  on('ui.render', () => h('Text', null, '') as never)
  on('turn.step', async function* (_$, e) {
    const u = usage()
    yield { kind: 'stop', stopReason: 'end_turn', usage: u } as never
    return { turnId: e.turnId, index: e.index, answer: 'ok', toolUses: [], stopReason: 'end_turn', usage: u } as never
  })
  return w
}

const hit = (model = 'claude-fable-5-1'): TurnUsage => ({
  model, input_tokens: 300, output_tokens: 50, cache_read_input_tokens: 150_000, cache_creation_input_tokens: 2_000,
})
const miss = (model = 'claude-fable-5-1'): TurnUsage => ({
  model, input_tokens: 300, output_tokens: 50, cache_read_input_tokens: 0, cache_creation_input_tokens: 152_000,
})

const START = { cwd: '/tmp', surface: 'terminal', isInteractive: true } as const
const step = (index = 0, agentId?: string, model = 'claude-fable-5-1'): TurnStepInput =>
  ({ turnId: 't1', index, model, messageCount: 3, ...(agentId ? { agentId } : {}) }) as TurnStepInput
const usage = (read: number, written: number): TurnUsage => ({
  model: 'claude-fable-5-1', input_tokens: 300, output_tokens: 50, cache_read_input_tokens: read, cache_creation_input_tokens: written,
})
const SUMMARY = [{ role: 'user', text: 'summary of the conversation so far', toolUses: [] }]
const end = (reason: string) => ({ reason, sessionId: 's1', resume: { id: 's1' } }) as never

const drain = async (s: AsyncIterable<unknown>) => { for await (const _ of s) { /* read to the end */ } }

test('a main-thread request starts the window; the status counts it down and warns near the end', async ($, on) => {
  let u: TurnUsage | null = hit()
  const w = world(on, () => u)
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)

  await drain($.turn.step(step()))
  await clock.settle()
  expect(w.status.at(-1)).toMatch(/^cache (59m|60m)$/)

  await clock.advance(30 * MIN)
  expect(w.status.at(-1)).toMatch(/^cache 30m$/)
  expect(w.toasts).toHaveLength(0)

  await clock.advance(25 * MIN + 10_000)
  expect(w.status.at(-1)).toMatch(/left ⚠$/)
  expect(w.toasts).toHaveLength(1)
  expect(w.toasts[0]).toMatch(/lapses in (5m00s|4m)/)

  await clock.advance(6 * MIN)
  expect(w.status.at(-1)).toMatch(/^cache COLD/)
  // Still one toast: the warning fires once per window.
  expect(w.toasts).toHaveLength(1)

  // A new request resets the window and re-arms the warning.
  u = hit()
  await drain($.turn.step(step(1)))
  await clock.settle()
  expect(w.status.at(-1)).toMatch(/^cache (59m|60m)$/)
})

test('a subagent request leaves the main window alone', async ($, on) => {
  const w = world(on, () => hit())
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.advance(20 * MIN)
  await drain($.turn.step(step(0, 'agent-1')))
  await clock.settle()
  expect(w.status.at(-1)).toMatch(/^cache 40m$/)
})

test('the first request of a session is a cold write, not a miss', async ($, on) => {
  const w = world(on, () => miss())
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.settle()
  expect(w.toasts).toHaveLength(0)
  expect(w.status.at(-1)).not.toMatch(/MISS/)

  const ran = await $.command.run({ command: 'cache', args: '' } as never)
  expect(ran.text).toMatch(/Last request: cold write \(expected: first request\)/)

  const PROPS = { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 9 } }
  const ui = await $.ui.mount({ plugin: 'cache-clock', surface: 'terminal', component: 'AbovePrompt', props: PROPS as never })
  expect(await ui.find({ type: 'Text', text: /MISS/ })).toBeUndefined()
  await ui.unmount()
})

test('a full write after the TTL lapsed is a cold write, not a miss', async ($, on) => {
  let u: TurnUsage | null = hit()
  const w = world(on, () => u)
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.advance(61 * MIN)
  u = miss()
  await drain($.turn.step(step(1)))
  await clock.settle()
  expect(w.toasts.filter(t => /MISS/.test(t))).toHaveLength(0)
  expect(w.status.at(-1)).not.toMatch(/MISS/)
})

test('a miss inside the window is flagged in status, toast and /cache', async ($, on) => {
  let u: TurnUsage | null = hit()
  const w = world(on, () => u)
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)

  await drain($.turn.step(step()))
  await clock.settle()
  expect(w.toasts).toHaveLength(0)

  await clock.advance(10 * MIN)
  u = miss()
  await drain($.turn.step(step(1)))
  await clock.settle()
  expect(w.status.at(-1)).toMatch(/MISS$/)
  expect(w.toasts).toHaveLength(1)
  expect(w.toasts[0]).toMatch(/Cache MISS 10m after the last request, 50m left on the clock: the TTL may have dropped to 5m/)
  expect(w.toasts[0]).toMatch(/Rewrote 152k tokens/)

  const ran = await $.command.run({ command: 'cache', args: '' } as never)
  expect(ran.text).toMatch(/Cache warm: (59m|60m) of 60m left/)
  expect(ran.text).toMatch(/Last request: MISS · read 0 · wrote 152,000/)

  // The MISS tag drops off the status line after a few minutes.
  await clock.advance(4 * MIN)
  expect(w.status.at(-1)).not.toMatch(/MISS/)
})

test('the band stays out of the way until the window nears its end, then draws a bar on every surface', async ($, on) => {
  world(on, () => hit())
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.settle()

  const PROPS = { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 9 } }
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'cache-clock', surface, component: 'AbovePrompt', props: PROPS as never })
    expect(await ui.find({ type: 'Text', text: /cache lapses/ })).toBeUndefined()
    await ui.unmount()
  }

  await clock.advance(56 * MIN)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'cache-clock', surface, component: 'AbovePrompt', props: PROPS as never })
    const line = await ui.find({ type: 'Text', text: /cache lapses in 4m/ })
    expect(line).toBeDefined()
    expect(line?.text).toMatch(/^█+░+ /)
    await ui.unmount()
  }

  // Cold: no bar, an all-empty one reads as broken glyphs.
  await clock.advance(10 * MIN)
  const ui = await $.ui.mount({ plugin: 'cache-clock', surface: 'terminal', component: 'AbovePrompt', props: PROPS as never })
  const cold = await ui.find({ type: 'Text', text: /cache COLD/ })
  expect(cold?.text).toMatch(/^cache COLD/)
  await ui.unmount()
})

test('/cache before any request says so', async ($, on) => {
  world(on, () => hit())
  mock.clock(on)
  await $.session.start(START)
  const ran = await $.command.run({ command: 'cache', args: '' } as never)
  expect(ran.text).toMatch(/No model request yet/)
})

test('ttlMinutes and warnMinutes come from the config', { options: { ttlMinutes: 5, warnMinutes: 2 } }, async ($, on) => {
  const w = world(on, () => hit())
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.advance(3 * MIN + 10_000)
  expect(w.status.at(-1)).toMatch(/left ⚠$/)
  expect(w.toasts[0]).toMatch(/resets the 5m window/)
})

test('a miss under 5m after the last request blames the prefix, not the TTL', async ($, on) => {
  let u: TurnUsage | null = hit()
  const w = world(on, () => u)
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.advance(2 * MIN)
  u = miss()
  await drain($.turn.step(step(1)))
  await clock.settle()
  expect(w.toasts).toHaveLength(1)
  expect(w.toasts[0]).toMatch(/the prompt prefix changed/)
  expect(w.toasts[0]).not.toMatch(/TTL/)
})

test('a full write after compaction is a cold write, not a miss', async ($, on) => {
  let u: TurnUsage | null = hit()
  const w = world(on, () => u)
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.advance(10 * MIN)
  await $.session.compact({ trigger: 'auto', messages: SUMMARY } as never)
  u = miss()
  await drain($.turn.step(step(1)))
  await clock.settle()
  expect(w.toasts).toHaveLength(0)
  expect(w.status.at(-1)).not.toMatch(/MISS/)
  const ran = await $.command.run({ command: 'cache', args: '' } as never)
  expect(ran.text).toMatch(/cold write \(expected: compaction\)/)

  // The flag lasts one request: a miss after that is a miss again.
  await clock.advance(MIN)
  await drain($.turn.step(step(2)))
  await clock.settle()
  expect(w.status.at(-1)).toMatch(/MISS$/)
})

test('a precomputed compaction installs nothing and keeps the next miss a miss', async ($, on) => {
  let u: TurnUsage | null = hit()
  const w = world(on, () => u)
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.advance(10 * MIN)
  await $.session.compact({ trigger: 'precompute', messages: SUMMARY } as never)
  u = miss()
  await drain($.turn.step(step(1)))
  await clock.settle()
  expect(w.status.at(-1)).toMatch(/MISS$/)
})

test('a model switch makes the next full write a cold write', async ($, on) => {
  let u: TurnUsage | null = hit()
  const w = world(on, () => u)
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.advance(10 * MIN)
  u = miss('claude-opus-5-5')
  await drain($.turn.step(step(1, undefined, 'claude-opus-5-5')))
  await clock.settle()
  expect(w.toasts).toHaveLength(0)
  const ran = await $.command.run({ command: 'cache', args: '' } as never)
  expect(ran.text).toMatch(/cold write \(expected: model switch\)/)
})

test('a big paste on a small context is not a miss: the old prefix was still read', async ($, on) => {
  let u: TurnUsage | null = usage(0, 15_000)
  const w = world(on, () => u)
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.advance(MIN)
  u = usage(15_000, 25_000)
  await drain($.turn.step(step(1)))
  await clock.settle()
  expect(w.toasts).toHaveLength(0)
  expect(w.status.at(-1)).not.toMatch(/MISS/)
})

test('/clear starts the clock over and keeps it ticking; a real exit stops it', async ($, on) => {
  let u: TurnUsage | null = hit()
  const w = world(on, () => u)
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.advance(10 * MIN)
  await $.session.end(end('clear'))
  expect(w.status.at(-1)).toBeUndefined()

  // No session.start follows a /clear; the next request still drives the clock.
  u = miss()
  await drain($.turn.step(step()))
  await clock.settle()
  expect(w.toasts).toHaveLength(0)
  await clock.advance(20 * MIN)
  expect(w.status.at(-1)).toMatch(/^cache 40m$/)

  await $.session.end(end('prompt_input_exit'))
  const n = w.status.length
  await clock.advance(20 * MIN)
  expect(w.status.length).toBe(n)
})

test('hours past the TTL read as hours', async ($, on) => {
  const w = world(on, () => hit())
  const clock = mock.clock(on, { now: 1_000_000 })
  await $.session.start(START)
  await drain($.turn.step(step()))
  await clock.advance(598 * MIN)
  expect(w.status.at(-1)).toMatch(/^cache COLD \(8h5[78]m past TTL\)$/)
})

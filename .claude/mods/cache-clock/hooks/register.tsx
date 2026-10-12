import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, TurnUsage } from 'claude-code'

import type { CacheLastStep, CacheWindow } from '../types'

const TICK_MS = 10_000
const MISS_BAND_MS = 3 * 60_000

const window = atom({ plugin: 'cache-clock', key: 'window' } as const, null)
const last = atom({ plugin: 'cache-clock', key: 'last' } as const, null)

const num = (v: unknown, fallback: number) =>
  typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : fallback

const mmss = (ms: number) => {
  const s = Math.max(0, Math.round(ms / 1000))
  const m = Math.floor(s / 60)
  return m >= 10 ? `${m}m` : `${m}m${String(s % 60).padStart(2, '0')}s`
}

const bar = (fraction: number, cells = 12) => {
  const lit = Math.max(0, Math.min(cells, Math.round(fraction * cells)))
  return '▮'.repeat(lit) + '▯'.repeat(cells - lit)
}


type Config = { ttlMs: number; warnMs: number; missTokens: number }
// Module-level: lost on a reload, which costs at worst one repeated toast.
const mem: { warnedFor: number | null } = { warnedFor: null }

async function refresh($: EngineInterface, cfg: Config) {
  const { ttlMs, warnMs } = cfg
  const now = await $.clock.now()
  const w = await read($, window)
  if (w === null) {
    $.ui.status(undefined)
    return
  }
  const remaining = ttlMs - (now - w.startedAt)
  const l = await read($, last)
  const missTag = l?.isMiss && now - l.at < MISS_BAND_MS ? ' · MISS' : ''

  if (remaining <= 0) {
    $.ui.status(`cache COLD (${mmss(-remaining)} past TTL)${missTag}`)
  } else if (remaining <= warnMs) {
    $.ui.status(`cache ${mmss(remaining)} left ⚠${missTag}`)
    if (mem.warnedFor !== w.startedAt) {
      mem.warnedFor = w.startedAt
      $.ui.toast(`Prompt cache lapses in ${mmss(remaining)}. Any prompt resets the ${Math.round(ttlMs / 60_000)}m window.`, { timeoutMs: 8000 })
    }
  } else {
    $.ui.status(`cache ${mmss(remaining)}${missTag}`)
  }
  // Coarse clock the band redraws from; one write per tick, not per ms.
  if (now - w.now >= TICK_MS - 500) await update($, window, cur => (cur ? { ...cur, now } : cur))
}

async function note($: EngineInterface, cfg: Config, usage: TurnUsage, at: number, previous: CacheWindow | null) {
  const { ttlMs, missTokens } = cfg
  const read_ = usage.cache_read_input_tokens
  const written = usage.cache_creation_input_tokens
  const isMiss = written >= missTokens && read_ < written
  const step: CacheLastStep = { at, isMiss, read: read_, written, uncached: usage.input_tokens, model: usage.model }
  await update($, last, () => step)
  // A miss while the window should still have been warm means the TTL is not what we assume.
  const wasExpected = previous === null || at - previous.startedAt >= ttlMs
  if (isMiss && !wasExpected) {
    $.ui.toast(`Cache MISS with ${mmss(ttlMs - (at - previous.startedAt))} left on the clock: TTL may have dropped to 5m. Rewrote ${Math.round(written / 1000)}k tokens.`, { timeoutMs: 10_000 })
  }
}

export const register: Register = (on, options) => {
  const cfg: Config = {
    ttlMs: num(options.ttlMinutes, 60) * 60_000,
    warnMs: num(options.warnMinutes, 5) * 60_000,
    missTokens: num(options.missTokens, 20_000),
  }
  const { ttlMs, warnMs } = cfg
  let tick: { cancel: () => void } | null = null

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'cache',
      description: 'Prompt-cache window: time left, last request hit or miss, token counts',
    })
    tick?.cancel()
    tick = $.clock.every(TICK_MS, () => { void refresh($, cfg) })
    return next(e)
  })

  on('session.end', ($, e, next) => {
    tick?.cancel()
    tick = null
    $.ui.status(undefined)
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    // A subagent's request has its own prefix; only main-thread requests touch the main cache.
    const isMain = e.agentId === undefined
    const startedAt = await $.clock.now()
    const previous = isMain ? await read($, window) : null
    if (isMain) await update($, window, () => ({ startedAt, now: startedAt }))

    const stream = next(e)
    for await (const chunk of stream) {
      if (isMain && chunk.kind === 'stop' && chunk.usage) {
        await note($, cfg, chunk.usage, startedAt, previous)
      }
      yield chunk
    }
    if (isMain) void refresh($, cfg)
    return stream.result
  })

  on('command.run', { command: 'cache' }, async $ => {
    const now = await $.clock.now()
    const w = await read($, window)
    const l = await read($, last)
    if (w === null) return { text: 'No model request yet this session; the cache clock starts on the first one.' }
    const remaining = ttlMs - (now - w.startedAt)
    const lines = [
      remaining > 0
        ? `Cache warm: ${mmss(remaining)} of ${Math.round(ttlMs / 60_000)}m left (TTL counts from the start of the last request).`
        : `Cache cold: TTL passed ${mmss(-remaining)} ago. The next request rewrites the whole context at 2× input price.`,
    ]
    if (l) {
      lines.push(
        `Last request: ${l.isMiss ? 'MISS' : 'hit'} · read ${l.read.toLocaleString()} · wrote ${l.written.toLocaleString()} · uncached ${l.uncached.toLocaleString()} · ${l.model}`,
      )
    }
    return { text: lines.join('\n') }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const w = await read($, window)
    if (e.props.hasSurvey || w === null) return next(e)
    const l = await read($, last)
    const now = Math.max(w.now, l?.at ?? 0)
    const remaining = ttlMs - (now - w.startedAt)
    const showMiss = l?.isMiss === true && now - l.at < MISS_BAND_MS
    const showWarn = remaining <= warnMs
    if (!showMiss && !showWarn) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const color = remaining <= 0 ? 'error' : remaining <= warnMs / 2 ? 'error' : 'warning'
    return (
      <Box flexDirection="column">
        {showWarn ? (
          <Text color={color}>
            {bar(remaining / ttlMs)}{' '}
            {remaining > 0
              ? `cache lapses in ${mmss(remaining)} · any prompt resets the window`
              : `cache COLD · next request pays a full context rewrite`}
          </Text>
        ) : null}
        {showMiss && l ? (
          <Text color="error">
            cache MISS on last request · rewrote {Math.round(l.written / 1000)}k tokens, read {Math.round(l.read / 1000)}k
          </Text>
        ) : null}
      </Box>
    )
  })
}

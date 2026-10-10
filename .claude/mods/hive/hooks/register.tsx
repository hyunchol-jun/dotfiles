import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { EnvSnapshot, Side } from '../types'

// The capture plugin's own kill switch is the single source of truth: a session is HIVE exactly
// when capture.sh would upload it. The launcher sets it; nothing in-session can change it.
const APIARY_TOOL = /^mcp__[A-Za-z0-9_]*apiary[A-Za-z0-9_]*__/i
const AMBER = '#f5b700'
const DARK = '#2a1f00'
const RED = '#c62828'
const GREEN = '#2e7d32'
const GREY = '#444444'

// The standing instruction apiaryOs onboarding would put in ~/.claude/CLAUDE.md, applied to HIVE
// sessions only, so plain sessions never try a tool they do not have.
const HIVE_PROMPT = `This is a HIVE session: apiaryOs is live and this transcript is captured to apiaryOs conversation memory.

## apiaryOs (Implentio)
apiaryOs is Implentio's default tool gateway and the primary tool for all Implentio work (brands, invoices, billers, reconciliation, onboarding, Implentio systems and data).
- In a conversation about Implentio work, call the apiaryOs \`session_start\` tool first and follow its next_action. Subagents do not need to call it.
- When the person uses an Implentio term you are not certain of, look them all up in one \`term_lookup\` call before investigating or reading code.
- Every time a distinct problem comes into focus, and again whenever it changes, call \`conversation_search\` with it before investigating. Start from where the closest past resolution ended, re-verify it against the current state, and say what you found ("I found other Implentio conversations around this: ...").
- Prefer apiaryOs tools over any other way of reading or changing Implentio systems. Fall back to local skills (implentio-db, trino, argo, kubectl) only for what apiaryOs cannot do yet.

### I drive, you execute
In Implentio work, the person owns the framing, the criteria and the decision; you execute and challenge their reasoning.
- Routine work (drafting from notes, edits, summaries, formatting, code to a clear spec, lookups): just do it.
- If asked to decide with no view given, first ask one short question for their position, criteria and constraints. If they have none, lay out the options and trade-offs and leave the choice to them.
- When they share a view, test it: weak assumptions, missing facts, the strongest counterargument. Do not just agree.
- On high-stakes calls (credit memos, rates, customer commitments, legal, personnel, strategy), say the decision is theirs and what they should verify.
- Flag facts or figures that may be wrong or stale, and how to check them.
- Never lecture about AI use. Subagents skip this section.`

// ---- environment tint (PLAN.md § E) ------------------------------------------------------------

type Config = {
  tunnelEnvDir: string
  tunnelEnvPrefix: string
  prodWords: string[]
  devWords: string[]
  ports: { trino: number; api: number }
  pollMs: number
}

// Defaults match Implentio today; hive.config.json at the mod root overrides any field.
const DEFAULTS: Config = {
  tunnelEnvDir: '/tmp',
  tunnelEnvPrefix: 'implentio-db-',
  prodWords: ['production', 'prod'],
  devWords: ['development', 'dev'],
  ports: { trino: 40080, api: 9001 },
  pollMs: 15000,
}

const envState = atom({ plugin: 'hive', key: 'env' } as const, null as EnvSnapshot | null)

type Dollar = EngineInterface

const classify = (cfg: Config, s: string | null | undefined): Side | null => {
  if (!s) return null
  const t = s.toLowerCase()
  if (cfg.prodWords.some(w => t.includes(w))) return 'prod'
  if (cfg.devWords.some(w => t.includes(w))) return 'dev'
  return null
}

const loadConfig = async ($: Dollar): Promise<Config> => {
  let text: string
  try {
    const root = $.plugin.root
    text = await $.fs.read(root + '/hive.config.json')
  } catch {
    return DEFAULTS
  }
  try {
    const got = JSON.parse(text) as Partial<Config>
    return { ...DEFAULTS, ...got, ports: { ...DEFAULTS.ports, ...(got.ports ?? {}) } }
  } catch {
    $.ui.toast('hive: hive.config.json is not valid JSON; using defaults', { timeoutMs: 6000 })
    return DEFAULTS
  }
}

const run = async ($: Dollar, argv: string[], timeoutMs = 3000) => {
  try {
    return await $.process.run(argv, { timeoutMs })
  } catch {
    return null
  }
}

// bash's /dev/tcp is on every mac and Linux box; lsof/ss/nc are not.
const listening = async ($: Dollar, port: number): Promise<boolean | null> => {
  const r = await run($, ['bash', '-c', 'exec 3<>/dev/tcp/127.0.0.1/' + port], 2000)
  return r === null ? null : r.exitCode === 0
}

const probe = async ($: Dollar, cfg: Config): Promise<EnvSnapshot> => {
  const db: EnvSnapshot['db'] = []
  try {
    const entries = await $.fs.list(cfg.tunnelEnvDir)
    for (const en of entries) {
      if (!en.name.startsWith(cfg.tunnelEnvPrefix) || !en.name.endsWith('.env')) continue
      const env = en.name.slice(cfg.tunnelEnvPrefix.length, -'.env'.length)
      let port: string | null = null
      try {
        // Only the PORT line is read into memory as a value; the credentials stay in the file.
        const m = /^PORT=(\d+)$/m.exec(await $.fs.read(cfg.tunnelEnvDir + '/' + en.name))
        port = m?.[1] ?? null
      } catch { /* unreadable: still a tunnel */ }
      db.push({ env, side: classify(cfg, env), port })
    }
  } catch { /* no such dir: no tunnels */ }

  const kubeRun = await run($, ['kubectl', 'config', 'current-context'])
  const kube = kubeRun && kubeRun.exitCode === 0 ? kubeRun.stdout.trim() || null : null

  const [trino, apiUp] = await Promise.all([listening($, cfg.ports.trino), listening($, cfg.ports.api)])

  let farEnd: Side | null = null
  if (apiUp) {
    const ps = await run($, ['ps', '-axo', 'args'])
    const line = ps?.stdout.split('\n').find(l => l.includes(String(cfg.ports.api)) && /ssh|kubectl|port-forward|socat/.test(l))
    farEnd = classify(cfg, line)
  }

  const sides = [...db.map(d => d.side), classify(cfg, kube), farEnd]
  const verdict: EnvSnapshot['verdict'] = sides.includes('prod') ? 'prod' : sides.includes('dev') ? 'dev' : 'none'
  return { at: await $.clock.now(), db, kube, trino, api: { listening: apiUp, farEnd }, verdict }
}

const dbLabel = (d: EnvSnapshot['db'][number]) => d.env + (d.port ? ' :' + d.port : '')

const summarize = (s: EnvSnapshot, cfg: Config): string[] => {
  const db = s.db.length ? s.db.map(dbLabel).join(', ') : 'none'
  const yn = (v: boolean | null) => (v === null ? '?' : v ? 'listening' : 'closed')
  return [
    'DB tunnel: ' + db + (s.db.length ? ' (read-only)' : ''),
    'kube context: ' + (s.kube ?? '?'),
    'trino :' + cfg.ports.trino + ': ' + yn(s.trino),
    'api :' + cfg.ports.api + ': ' + yn(s.api.listening) + (s.api.farEnd ? ', far end ' + s.api.farEnd : ''),
  ]
}

const bandText = (s: EnvSnapshot, cfg: Config) => {
  const mark = (v: boolean | null) => (v === null ? '?' : v ? '✓' : '✗')
  const db = s.db.length ? s.db.map(dbLabel).join(' + ') : 'no tunnel'
  const api = ':' + cfg.ports.api + ' ' + mark(s.api.listening) + (s.api.farEnd ? ' → ' + s.api.farEnd : '')
  const head = s.verdict === 'prod' ? '⛔ PROD' : s.verdict === 'dev' ? '● dev' : '○ local'
  return ' ' + head + ' · DB ' + db + ' · kube ' + (s.kube ?? '?') + ' · trino :' + cfg.ports.trino + ' ' + mark(s.trino) + ' · api ' + api + ' '
}

// ---- register ------------------------------------------------------------------------------------

// Mutable per-load runtime; a reload starts it over, the atom's value stays.
type Runtime = { cfg: Config; inFlight: boolean; lastSummary: string }

async function refresh($: Dollar, rt: Runtime): Promise<void> {
  if (rt.inFlight) return
  rt.inFlight = true
  try {
    const snap = await probe($, rt.cfg)
    await update($, envState, () => snap)
    const summary = summarize(snap, rt.cfg).join('\n')
    if (summary !== rt.lastSummary) {
      rt.lastSummary = summary
      $.ui.invalidate('prompt.context')
    }
  } finally {
    rt.inFlight = false
  }
}

export const register: Register = on => {
  let isHive = false
  const rt: Runtime = { cfg: DEFAULTS, inFlight: false, lastSummary: '' }
  let timer: { cancel: () => void } | null = null

  on('session.start', async ($, e, next) => {
    // Only an explicit 0 (set by bin/hive) makes a HIVE session. Unset means plain, and the mod
    // pins the kill switch so capture.sh sees it too, without any shell-side wrapper for `claude`.
    isHive = (await $.env.get('APIARY_CAPTURE_DISABLED')) === '0'
    if (!isHive) await $.env.set('APIARY_CAPTURE_DISABLED', '1')
    await $.command.register({
      name: 'hive',
      description: 'Say whether this session is HIVE (apiaryOs live, transcript uploads) or plain',
    })
    await $.command.register({
      name: 'env',
      description: 'Which environment your local tunnels point at (DB tunnel, kube context, Trino, api :9001)',
    })
    if (isHive) {
      $.ui.status('🐝 HIVE')
      $.ui.toast('🐝 HIVE session: apiaryOs is live and every turn uploads to conversation memory', { timeoutMs: 8000 })
      void $.audio.play({ asset: 'fx/hive.wav' }).catch(() => undefined)
    }
    rt.cfg = await loadConfig($)
    await refresh($, rt)
    timer?.cancel()
    timer = $.clock.every(rt.cfg.pollMs, () => void refresh($, rt))
    return next(e)
  })

  on('session.end', ($, e, next) => {
    timer?.cancel()
    timer = null
    return next(e)
  })

  on('command.run', { command: 'hive' }, () => ({
    text: isHive
      ? '🐝 HIVE session. apiaryOs tools are live and this transcript uploads to apiaryOs conversation memory. Fixed at launch; start a plain `claude` to leave.'
      : 'Plain session. apiaryOs tools are refused and nothing uploads. Fixed at launch; start `hive` to use apiaryOs.',
  }))

  on('command.run', { command: 'env' }, async $ => {
    await refresh($, rt)
    const s = await read($, envState)
    if (!s) return { text: 'hive: environment not probed yet.' }
    const age = Math.round(((await $.clock.now()) - s.at) / 1000)
    return { text: ['verdict: ' + s.verdict, ...summarize(s, rt.cfg), 'checked ' + age + 's ago, every ' + rt.cfg.pollMs / 1000 + 's'].join('\n') }
  })

  // Belt for a plain session that still has the server configured somewhere.
  on('tool.call', ($, e, next) =>
    !isHive && APIARY_TOOL.test(e.tool)
      ? { deny: 'hive: apiaryOs is off in this plain session. Use local skills (implentio-db, trino, argo), or ask the person to relaunch with `hive`.' }
      : next(e),
  ).catch(($, e, next) => (next.called ? next(e) : { deny: 'hive: its guard failed; apiaryOs refused.' }))

  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    const text = isHive
      ? HIVE_PROMPT
      : 'This is a plain session: apiaryOs is not loaded and every apiaryOs MCP tool is refused here. Do not call them; use local skills instead. If the person asks for an apiaryOs tool (session_start, conversation_search, brand_list, ...), answer in one line that apiaryOs is not in this session and that a `hive` session has it. Never improvise a stand-in answer. apiaryOs cannot be enabled mid-session.'
    return { sections: [...r.sections, { id: 'hive:mode', text, scope: 'session' }] }
  })

  // One block so the model knows which far end the local tunnels reach instead of guessing.
  on('prompt.context', async ($, e, next) => {
    const s = await read($, envState)
    if (!s) return next(e)
    const lines = summarize(s, rt.cfg)
    const verdict =
      s.verdict === 'prod'
        ? 'At least one local connection reaches PRODUCTION. Treat DB/Trino/api work in this session as production: read-only unless the person explicitly asks for a write, and say "production" when you report results.'
        : s.verdict === 'dev'
          ? 'Local connections reach DEVELOPMENT only. Do not describe results as production data.'
          : 'No DB tunnel or port-forward is open. Say so before suggesting a query; do not assume one.'
    const text = 'Local environment, probed by the hive mod every ' + rt.cfg.pollMs / 1000 + 's (run /env for the latest):\n' + lines.map(l => '- ' + l).join('\n') + '\n' + verdict
    return next({ ...e, blocks: [...e.blocks, { name: 'hive-env', text }] })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const snap = await read($, envState)
    if (!isHive && !snap) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const w = e.props.bodyColumns ?? 80
    const fill = (label: string) => label + ' '.repeat(Math.max(0, w - label.length - 1))
    const envBg = !snap ? GREY : snap.verdict === 'prod' ? RED : snap.verdict === 'dev' ? GREEN : GREY
    return (
      <Box flexDirection="column">
        {isHive ? (
          <Box backgroundColor={AMBER} width={w}>
            <Text color={DARK} bold>{fill(' 🐝  HIVE · apiaryOs LIVE · this conversation uploads to apiaryOs memory ')}</Text>
          </Box>
        ) : null}
        {snap ? (
          <Box backgroundColor={envBg} width={w}>
            <Text color="#ffffff" bold={snap.verdict === 'prod'}>{fill(bandText(snap, rt.cfg))}</Text>
          </Box>
        ) : null}
        {isHive ? (
          <Box backgroundColor={DARK} width={w}>
            <Text color={AMBER}>{'▰'.repeat(Math.max(1, w - 1))}</Text>
          </Box>
        ) : null}
      </Box>
    )
  })

  on('ui.render', { component: 'SessionMode' }, ($, e, next) =>
    isHive ? next({ ...e, props: { ...e.props, modes: ['🐝 HIVE', ...e.props.modes] } }) : next(e),
  )

  on('ui.render', { component: 'Spinner' }, ($, e, next) =>
    isHive ? next({ ...e, props: { ...e.props, word: 'Buzzing' } }) : next(e),
  )

  // Every prompt row carries the mark, so scrollback says which kind of session it was.
  on('ui.render', { component: 'UserMessage' }, ($, e, next) =>
    isHive && e.props.origin.kind === 'composer' ? next({ ...e, props: { ...e.props, text: `🐝 ${e.props.text}` } }) : next(e),
  )
}

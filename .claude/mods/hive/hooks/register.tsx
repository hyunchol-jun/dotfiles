import type { Register } from 'claude-code'

// The capture plugin's own kill switch is the single source of truth: a session is HIVE exactly
// when capture.sh would upload it. The launcher sets it; nothing in-session can change it.
const APIARY_TOOL = /^mcp__[A-Za-z0-9_]*apiary[A-Za-z0-9_]*__/i
const AMBER = '#f5b700'
const DARK = '#2a1f00'

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

export const register: Register = on => {
  let isHive = false
  on('session.start', async ($, e, next) => {
    // Only an explicit 0 (set by bin/hive) makes a HIVE session. Unset means plain, and the mod
    // pins the kill switch so capture.sh sees it too, without any shell-side wrapper for `claude`.
    isHive = (await $.env.get('APIARY_CAPTURE_DISABLED')) === '0'
    if (!isHive) await $.env.set('APIARY_CAPTURE_DISABLED', '1')
    await $.command.register({
      name: 'hive',
      description: 'Say whether this session is HIVE (apiaryOs live, transcript uploads) or plain',
    })
    if (isHive) {
      $.ui.status('🐝 HIVE')
      $.ui.toast('🐝 HIVE session: apiaryOs is live and every turn uploads to conversation memory', { timeoutMs: 8000 })
      void $.audio.play({ asset: 'fx/hive.wav' }).catch(() => undefined)
    }
    return next(e)
  })

  on('command.run', { command: 'hive' }, () => ({
    text: isHive
      ? '🐝 HIVE session. apiaryOs tools are live and this transcript uploads to apiaryOs conversation memory. Fixed at launch; start a plain `claude` to leave.'
      : 'Plain session. apiaryOs tools are refused and nothing uploads. Fixed at launch; start `hive` to use apiaryOs.',
  }))

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

  on('ui.render', { component: 'AbovePrompt' }, ($, e, next) => {
    if (!isHive || e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const w = e.props.bodyColumns ?? 80
    const label = ' 🐝  HIVE · apiaryOs LIVE · this conversation uploads to apiaryOs memory '
    const pad = Math.max(0, w - label.length - 1)
    return (
      <Box flexDirection="column">
        <Box backgroundColor={AMBER} width={w}>
          <Text color={DARK} bold>{label}{' '.repeat(pad)}</Text>
        </Box>
        <Box backgroundColor={DARK} width={w}>
          <Text color={AMBER}>{'▰'.repeat(Math.max(1, w - 1))}</Text>
        </Box>
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

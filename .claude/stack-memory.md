# Stack — project memory

This file is auto-loaded into Claude Code context at the start of every session
under ~/Implentio/stack (any worktree), via a SessionStart hook in
~/dotfiles/.claude/settings.json.

It lives in the dotfiles repo, so it syncs across machines (and is committed there).
Edit freely. Keep it concise; the whole file is injected every session.

## Context

<!-- e.g. what the stack repo is, the worktree layout, who uses it -->

## Conventions

<!-- e.g. branch naming, commit style, test commands, deploy steps -->

## Agent skills

Config for Matt Pocock's engineering skills (to-tickets, triage, to-spec, qa,
wayfinder, domain-modeling, ...). All of it is local/git-ignored — never commit
these files or add this section to a checked-in CLAUDE.md.

- **Issue tracker**: local markdown under `.scratch/` (git-ignored). See
  `~/Implentio/stack/main/docs/agents/issue-tracker.md`.
- **Triage labels**: the five defaults. See
  `~/Implentio/stack/main/docs/agents/triage-labels.md`.
- **Domain docs**: single-context. Generated docs (CONTEXT.md glossaries, ADRs) go
  under a git-ignored `docs-local/` at the root you're working from — NEVER into the
  checked-in `docs/` tree. See `~/Implentio/stack/main/docs/agents/domain.md`.

## Reminders

<!-- e.g. gotchas, things you keep forgetting, do/don't -->

## Explanation style (default)

When explaining a problem, bug, or design tradeoff, default to this style. Escalate to
deeper/more technical detail only when the topic genuinely needs it or I ask.

- **Lead with the core insight in plain language**, not jargon. Name the underlying
  mechanism in one phrase the way you'd say it out loud (e.g. "one query doing two jobs
  at once"), then build on it.
- **Anchor abstractions to something concrete** before generalizing — a specific table,
  query, invoice, or number, not just the concept.
- **When comparing approaches, label them** (Option 2 / Option 3) and for EACH give: what
  it does, and why it works or fails. Make the contrast explicit; don't make me infer it.
- **End with a one-line TL;DR** that contrasts the options or states the verdict.
- Minimize hedging and jargon-stacking. If a sentence needs three domain terms to parse,
  rewrite it.

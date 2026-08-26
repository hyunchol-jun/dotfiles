# Global Codex instructions

## Agent skills — Implentio stack repo only

Applies only when working under `~/Implentio/stack` (any worktree). Config for
Matt Pocock's engineering skills (to-tickets, triage, to-spec, wayfinder,
domain-modeling, ...). All of it is local/git-ignored — never commit these
files or add this section to a checked-in CLAUDE.md/AGENTS.md.

- **Issue tracker**: local markdown under `.scratch/` (git-ignored). See
  `~/Implentio/stack/main/docs/agents/issue-tracker.md`.
- **Triage labels**: the five defaults. See
  `~/Implentio/stack/main/docs/agents/triage-labels.md`.
- **Domain docs**: single-context. Generated docs (CONTEXT.md glossaries, ADRs)
  go under a git-ignored `docs-local/` at the root you're working from — NEVER
  into the checked-in `docs/` tree. See
  `~/Implentio/stack/main/docs/agents/domain.md`.

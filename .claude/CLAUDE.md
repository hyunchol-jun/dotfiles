Obsidian vault path: ~/Library/Mobile Documents/iCloud~md~obsidian/Documents/vimwiki

Stack project memory: ~/dotfiles/.claude/stack-memory.md
When I ask to add/save/remember something to "stack memory" (or for the stack project), edit that file. It is auto-loaded into context for sessions under ~/Implentio/stack.

## Plain language

Explain in plain language by default. Assume I'm smart but don't live inside this system's vocabulary.

- Say what happened in everyday words first; the technical name comes after, in parentheses, only if I'll need it to act (e.g. "the database copy fell behind (replication lag)").
- Use a technical term without translation only when it IS the action — an exact command, file path, table name, error string, or flag I must type or search for. Those stay verbatim.
- No unexplained acronyms or internal codenames. If a term appeared earlier in the conversation with an explanation, you may reuse it bare.
- Prefer cause-and-effect sentences ("X failed because Y, so Z happened") over terminology-dense summaries.
- If I ask a technical question using technical terms, match my level — this rule sets the default, not a ceiling.

## Machine constraints — host mini1 ONLY
Applies only when running on the host named mini1 (8GB Mac mini); ignore on other machines. On mini1: never run parallel builds or test suites with more than 2 workers (use --maxWorkers=2), and run one heavy task at a time. mini1 has a machine-wide 2GB node heap cap (NODE_OPTIONS in ~/.zshenv); if a legitimate task hits "JavaScript heap out of memory" there, rerun that one command with a higher --max-old-space-size.

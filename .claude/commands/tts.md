---
description: Toggle Telegram voice notes for this session (on | off | once)
allowed-tools: Bash(mkdir:*), Bash(touch:*), Bash(rm:*), Bash(ls:*), Bash(test:*)
---

Manage per-session Telegram voice notes (spoken by the tts-notify.sh Stop hook).

The flag directory is `~/.claude/.tts-sessions/` and this session's ID is in
`$CLAUDE_CODE_SESSION_ID`. Argument given: "$ARGUMENTS"

Do exactly one of the following based on the argument:

- **on**: run `mkdir -p ~/.claude/.tts-sessions && touch ~/.claude/.tts-sessions/$CLAUDE_CODE_SESSION_ID`, then confirm: voice notes are ON for this session.
- **off**: run `rm -f ~/.claude/.tts-sessions/$CLAUDE_CODE_SESSION_ID ~/.claude/.tts-sessions/$CLAUDE_CODE_SESSION_ID.once`, then confirm: voice notes are OFF for this session.
- **once**: run `mkdir -p ~/.claude/.tts-sessions && touch ~/.claude/.tts-sessions/$CLAUDE_CODE_SESSION_ID.once`, then confirm: only the next response will be spoken.
- **empty / anything else**: check which flag files exist for `$CLAUDE_CODE_SESSION_ID` (also check `~/.claude/tts-on` for the global always-on flag) and report the current state plus the available subcommands (on, off, once).

Keep the confirmation to one short sentence. Do not modify any other files.

## Speech-friendly responses

After **on**, write every final response speech-friendly for the rest of the
session; after **once**, only the next one; after **off**, write normally.

The Stop hook speaks the final response with code blocks, markdown, and URLs
stripped. So keep the prose self-sufficient — everything the listener needs
in plain, short, spoken-style sentences, leading with the outcome. Refer to
things pronounceably ("the tts-notify script", not a full path). Code blocks
and tables are still fine for the terminal reader; just don't let them carry
the message.

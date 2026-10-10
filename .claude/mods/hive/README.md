# hive — apiaryOs sessions in Claude Code, unmistakably on or off

A Claude Code mod plus a launcher. Two kinds of session, decided at launch, no in-session toggle:

| | `hive` | plain `claude` |
|---|---|---|
| apiaryOs MCP server | loaded from `apiaryos.mcp.json` | not loaded |
| transcript capture (apiary-capture) | ON (`APIARY_CAPTURE_DISABLED=0`) | OFF (mod pins `=1`) |
| apiaryOs tool calls | allowed | refused by a `tool.call` hook |
| system prompt | apiaryOs default-tool + "I drive, you execute" | "apiaryOs not here, use local skills, never improvise" |
| look | amber band, `🐝 HIVE` footer, 🐝 on your prompts, chime, pane tint | nothing |

`/hive` in either session says which one you are in.

## Environment row (both kinds of session)
A second band row says which far end your local connections reach, re-probed every 15s:

`⛔ PROD · DB production :51003 · kube production-primary · trino :40080 ✓ · api :9001 ✓ → prod`

Red if anything is production, green if only development, grey if nothing is open. The same facts
go into the model's context as a `hive-env` block, so it stops assuming dev (or prod). `/env` prints
them with the time of the last probe. Signals: `/tmp/implentio-db-<env>.env` written by the stack
repo's `connect-implentio-db` skill (only its `PORT` line is read), `kubectl config current-context`,
and a bash `/dev/tcp` probe of the Trino and api-v2 forward ports. Edit `hive.config.json` to change
paths, ports, or the words that mean prod/dev. The mod never opens a tunnel, only detects one.

## Why the env var, not the deny
apiary-capture uploads a session as soon as any apiaryOs `tool_use` lands in the transcript, and a
denied call still leaves that block there. So the deny is a belt; `APIARY_CAPTURE_DISABLED` is the
guarantee. `bin/hive` is the only thing that sets it to 0; the mod pins it to 1 otherwise.

## Install (any machine, mac or Linux)
Prereqs: Claude Code ≥ 2.1.296, the `apiary-capture@implentio` plugin (`/plugin`, marketplace URL in
the stack repo's `tools/claude-plugins/apiary-capture/README.md`).

1. Get this folder at `~/.claude/mods/hive`. In these dotfiles, `./install` links it (dotbot).
   Anywhere else: `git clone`/copy, then `ln -s <folder> ~/.claude/mods/hive`.
2. Add to your shell rc (bash or zsh, identical):
   ```sh
   claude() { APIARY_CAPTURE_DISABLED=1 command claude --plugin-dir ~/.claude/mods/hive "$@"; }
   export PATH="$HOME/.claude/mods/hive/bin:$PATH"
   ```
3. First `hive`: a browser opens for the Authentik login (once per machine; the OAuth token is
   shared across Claude Code scopes). Then run `/apiary-capture:setup` if capture isn't set up yet.
4. Do NOT `claude mcp add apiaryos` in user/project scope and do NOT add the apiaryOs block to
   `~/.claude/CLAUDE.md`. Both would leak apiaryOs into plain sessions.

## Platform notes
| Piece | Works on | If unsupported |
|---|---|---|
| mod (band, footer, prompt, deny, chime) | anywhere Claude Code runs | n/a |
| capture token | macOS Keychain, Linux Secret Service (`secret-tool`), Windows DPAPI file | see apiary-capture README |
| pane tint | tmux (any OS) | skipped |
| terminal background tint | Ghostty, kitty, WezTerm, foot, iTerm2 | ignored silently (Terminal.app, Windows Terminal) |

## Develop
```sh
cd ~/.claude/mods/hive
claude plugin validate . && claude plugin test .
```
Load the `plugin-authoring` skill in a session first; it writes the current build's type
definitions to `.claude-plugin/types/` (git-ignored). Roadmap in `PLAN.md`.

## Later, not now
Marketplace entry in the stack repo (`tools/claude-plugins/hive`) and a nix devshell `hive`
command would remove steps 1–2. Deliberately not done yet; see `PLAN.md` § open questions.

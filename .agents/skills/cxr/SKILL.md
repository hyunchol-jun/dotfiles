---
name: cxr
description: Launch a Codex computer-use session (cxr) in a tmux window to run a UI test or UI task in Chrome, then report its findings.
argument-hint: "URL + what to test or do (checks, expected outcomes)"
disable-model-invocation: true
---

# cxr — delegate a Chrome UI run to Codex

Launch a `cxr` session (Codex TUI attached to the local app-server, computer use enabled) in a detached tmux window, hand it a composed brief, wait for its findings file, and report the verdict.

Facts the environment won't tell you:

- `cxr` is a zsh alias (`~/dotfiles/zshrc`), so it only exists in an interactive zsh — launch it via `tmux send-keys` into a fresh window, never from a script or `sh -c`.
- Computer use needs the app-server; `codex exec` has no `--remote`, so the interactive TUI is the only vehicle. The session is interactive — the user can take over in the tmux window at any time.
- Codex cannot capture the Codex/ChatGPT app itself (self-capture block). Every other app works.
- The session runs `--yolo`: whatever the brief says, Codex will do without confirmation. Keep briefs scoped.

## Steps

1. **Guard.** The app-server runs only on mini1/mini2. Check `hostname` matches `mini1*`/`mini2*` and `nc -z 127.0.0.1 4500` succeeds. On failure, stop and tell the user; setup and troubleshooting live in `~/dotfiles/docs/codex-remote-computer-use.md`.

2. **Collect the brief.** From the user's arguments, extract: the URL, whether the page is already open in Chrome, and the work — either **test mode** (checks with expected outcomes) or **task mode** (an action to perform with a done-condition). If the URL or the work is missing, ask once for exactly what's missing; infer the rest.

3. **Write the run files.** `RUN=/tmp/cxr-runs/$(date +%Y%m%d-%H%M%S)`; `mkdir -p "$RUN"`. Write the composed brief (template below) to `$RUN/prompt.md`. The findings path inside the brief is `$RUN/findings.md` — spell it out absolute.

4. **Launch.** Detached window so the user's focus stays put:

   ```sh
   WIN=$(tmux new-window -dP -F '#{window_id}' -n cxr)
   tmux send-keys -t "$WIN" 'cxr "$(cat '"$RUN"'/prompt.md)"' Enter
   ```

   If not inside tmux, add `-t "$(tmux list-sessions -F '#S' | head -1)"` to `new-window`. Tell the user the session is running in tmux window `cxr` and where the run dir is.

5. **Wait and report.** Run in the background: `timeout 1800 sh -c 'until [ -f '"$RUN"'/findings.md ]; do sleep 10; done'`. When it exits:
   - Findings exist → read the file and report, verdict first, then the per-check or end-state detail. Done when the user has the verdict and the findings.
   - Timeout → report that the session is still running in window `cxr`, and that findings will appear at `$RUN/findings.md`. Done.

## Brief template

Fill `{…}`, drop lines that don't apply, keep the rest verbatim:

```
You are driving Google Chrome on this Mac via computer use.

Target: {URL}
{if already open} The page should already be open in Chrome — find that tab first; navigate to the URL only if you can't find it.
The session is already authenticated. Never attempt a login or enter credentials unless this brief explicitly says to.

{test mode} Checks — run every one, in order:
{numbered checks, each with its expected outcome}

{task mode} Task:
{the action, and the condition that means it's done}

Rules:
- Interact only with Chrome. The Codex/ChatGPT app cannot be captured — never target it.
- Stay on the target site except where a check or the task requires leaving it.
- If blocked (page won't load, unexpected auth wall, element missing), stop and record exactly what you saw instead of improvising around it.

Report — mandatory, including on failure or when blocked:
Write a markdown report to {absolute findings path}.
First line: VERDICT: {test mode: PASS | FAIL | BLOCKED}{task mode: DONE | FAILED | BLOCKED}.
{test mode} Then one section per check: what you did, what you observed, PASS or FAIL.
{task mode} Then: what you did, the end state of the page, anything unexpected.
The report file is the only channel back to your operator; the run counts as abandoned without it.
```

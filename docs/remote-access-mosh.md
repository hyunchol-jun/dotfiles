# Robust remote access to mini1 + mini2

Status: Layer 1 implemented 2026-08-18. Layer 2 (mini2 wi-fi) not started.
Layer 3 (HEAD mosh for the clipboard bug) specced 2026-09-14 — see "Layer 3" below.

## Context

The `mini1` and `mini2` aliases (`zshrc:81`, `zshrc:84`) SSH straight into a remote tmux. When the
connection dies you get dumped out and have to re-run the alias. tmux preserves the work — the cost
is the interruption, and it recurs.

**Both boxes must work from anywhere.** mini1 is always remote. mini2 is on the same LAN when you're
home, but remote when you work outside. Any fix has to be location-agnostic.

### Three independent causes of the drops

1. **Tailscale path flapping (affects both boxes, everywhere).** `tailscale ping mini2` was observed
   answering `via DERP(tok) in 177ms`, then upgrading to `via 192.168.219.104 in 89ms` — a
   relay-to-direct switch mid-session. Tailscale renegotiates the path whenever the network changes,
   and each flip can break a TCP connection. Moving between home and outside guarantees these.
2. **Your own network changing (affects both, when you work outside).** Leaving the house changes
   your IP entirely. SSH cannot survive that; every session dies.
3. **mini2's weak Wi-Fi (mini2, at home only).** On the *same* AP, channel, and band as the
   MacBook, mini2 gets **86 Mbps / MCS 4 at −67 dBm** vs the MacBook's **650 Mbps / MCS 7 at
   −59 dBm** — 7.5× worse. Its Ethernet port is empty (`media: autoselect (none)`) and a cable is
   impractical (another room). Sleep is ruled out: `sleep 0` on AC with a 92h prevent-sleep
   assertion.

Causes 1 and 2 matter most — they hit both machines and no amount of Wi-Fi tuning addresses them.
**Layer 1 fixes all three symptoms at once and is the whole fix for mini1; Layer 2 is
mini2-at-home polish.** Tailscale hardening was investigated and ruled out — see "Considered and
dropped" below.

**Ruled out:** an earlier theory that mini2 flaps between two APs on channel 36 — 90s of continuous
ping showed 0% loss and no dropout pattern. Do not reconfigure the router.

---

## Layer 1 — mosh on both boxes, driven by bootstrap

mosh runs over UDP, keeps its session identity across IP changes, resumes automatically, and its
predictive local echo hides latency while typing. With tmux (already in use), every one of the three
causes above degrades to a brief `[network disconnected]` in the status line instead of a logout.

### Why mosh is the right call *specifically* because of Tailscale

Mosh's usual objection is "hotel Wi-Fi blocks UDP." **That does not apply here.** Mosh's UDP travels
*inside* the Tailscale tunnel, and Tailscale itself falls back to a DERP relay over TCP/443 when
UDP is blocked. So mosh keeps working on restrictive networks — the exact situation where plain SSH
is least reliable.

Equally, no LAN-vs-remote logic is needed. Tailscale already picks the best path per location
automatically — confirmed: it chose the LAN address for mini2 (home) and the public address for
mini1 (remote), from the same single Tailscale IP. **The Tailscale IP is correct everywhere**, which
is why the existing `||` fallbacks can simply be deleted.

### Why this is already reproducible

Nothing new needs adding to `bootstrap.sh`. Two existing channels cover it:

| Need | Channel | Already wired? |
|---|---|---|
| Install mosh on a machine | `Brewfile` → `brew bundle` | Yes — `scripts/macos.sh:38` |
| Ship the aliases | `zshrc` → dotbot symlink | Yes — `install.conf.yaml` links `~/.zshrc` |

Both minis are confirmed ready: arm64, `/opt/homebrew`, `~/.zshrc → ~/dotfiles/zshrc`, same commit
(`41a3d7d`).

### 1.1 `Brewfile` — add one line

Alongside the other CLI formulae (near `brew "tmux"`, line 3):

```ruby
brew "mosh"
```

Single source of truth: every machine running bootstrap gets mosh, including future ones.

> Recorded gotcha: if mosh is ever uninstalled, Homebrew auto-runs `autoremove` and takes unrelated
> orphaned formulae with it — this removed `go` from mini2 during an earlier revert. Use
> `HOMEBREW_NO_AUTOREMOVE=1 brew uninstall mosh`.

### 1.2 `zshrc:80-84` — replace both aliases

Both current aliases have a `||` fallback where **both branches hit the same Tailscale IP**, so it
never did anything; the `mini1` comment ("over LAN, falls back to tailscale IP") is stale for the
same reason. Replace lines 80–84 with:

```zsh
# attach to a remote box's tmux over tailscale.
# mosh survives IP changes, tailscale path flips (DERP<->direct), and wifi drops,
# and resumes on its own. its UDP rides inside the tailscale tunnel, so it also works
# on networks that block UDP outright. predict=adaptive stays quiet on a fast LAN
# and turns on local echo automatically once latency climbs (i.e. when working outside).
# `-i`/IdentitiesOnly are passed explicitly rather than relying on ~/.ssh/config,
# which is untracked — keeps these working on a fresh machine.
_remote_mosh() {  # $1 = short name (for errors), $2 = user@host
  mosh --ssh="ssh -o IdentitiesOnly=yes -i $HOME/.ssh/id_ed25519 -o ConnectTimeout=15" \
       --server=/opt/homebrew/bin/mosh-server \
       --predict=adaptive \
       "$2" -- /opt/homebrew/bin/tmux attach \
    || { echo "mosh to $1 failed — check tailscale is connected, or try ${1}ssh" >&2; return 1; }
}

# plain-ssh fallback. also the path for anything mosh cannot do (scp, port forwarding).
_remote_ssh() {  # $1 = user@host
  ssh -t -o IdentitiesOnly=yes -i "$HOME/.ssh/id_ed25519" \
      -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ConnectTimeout=15 \
      "$1" /opt/homebrew/bin/tmux attach
}

alias mini1='_remote_mosh mini1 michaelkang@100.122.37.52'
alias mini2='_remote_mosh mini2 josephjun@100.119.210.87'
alias mini1ssh='_remote_ssh michaelkang@100.122.37.52'
alias mini2ssh='_remote_ssh josephjun@100.119.210.87'
```

Notes that matter:
- Alias names are unchanged — muscle memory intact.
- `$HOME` not `~`: tilde does not expand inside the double-quoted `--ssh=` string.
- `ConnectTimeout` raised 5 → 15 everywhere. The old 5s is too tight for a handshake over a DERP
  relay, which is exactly the path used when you're outside.
- Keep plain `tmux attach`, not `attach -d`. mosh resumes the *same* session rather than adding a
  client, so duplicates stop accumulating by themselves. `-d` would detach other clients — risky,
  since mini2 has a monitor attached and may have a local session. Run `tmux attach -d` by hand on
  the rare occasion a stale client shrinks your window.

### 1.3 Constraint: `*fwd` and `*send` stay on SSH

mosh supports **no port forwarding, no scp, no agent forwarding**. `mini1fwd`/`mini2fwd`
(`zshrc:90`, `zshrc:103`) and `mini1send`/`mini2send` (`zshrc:119`, `zshrc:139`) keep using
`ssh`/`scp`. Three changes to make them survive a remote path:

1. **Add keepalives** — they hold long-lived connections with none today and hang silently on a
   flaky link. Add `-o ServerAliveInterval=15 -o ServerAliveCountMax=4` to the `ssh -N` calls
   (`zshrc:98-99`, `zshrc:111-112`) and the `ssh_opts` arrays (`zshrc:128`, `zshrc:148`).
2. **Raise `ConnectTimeout` 5 → 15** in the same places, for the DERP-relay case.
3. **Delete `mini1send`'s dead LAN probe** (`zshrc:129-130`). `192.168.219.46` is now 100%
   unreachable — mini1 has moved off that LAN. The probe costs a guaranteed 5s timeout on every
   single call. Drop it and use the Tailscale IP directly, matching `mini2send`.

All inline in `zshrc`, **not** `~/.ssh/config` — that file is untracked and not dotbot-linked, so
changes there are not reproducible.

### 1.4 Optional: cap orphaned `mosh-server` processes

`mosh-server` persists indefinitely when a client vanishes uncleanly, and each orphan holds a tmux
client. To bound it, change the `--server` value to:

```zsh
--server="MOSH_SERVER_NETWORK_TMOUT=604800 /opt/homebrew/bin/mosh-server"
```

**One week, not one day** — deliberately, since you may be away from a box for a long stretch and a
short timeout would throw away the resume-without-reattach benefit. Safe either way: when
mosh-server exits the tmux session survives untouched.

Verify this form works during implementation — mosh appends its own args to the server command, so
the remote shell must accept the `VAR=value cmd` prefix. Skip it if it misbehaves; it's housekeeping,
not load-bearing.

**Deliberately not doing:** editing `~/.zshenv` on the minis to put `/opt/homebrew/bin` on the
non-interactive PATH. `.zshenv` is not dotbot-managed, so that change would be invisible to the repo
and would not survive a rebuild. The `--server=` absolute path solves it inside tracked config.

### 1.5 Rollout

```sh
# 1. commit + push from the MacBook
git add Brewfile zshrc && git commit && git push

# 2. on each mini — pull, then install just the new formula
ssh mini1 'cd ~/dotfiles && git pull && /opt/homebrew/bin/brew bundle --file=~/dotfiles/Brewfile --no-upgrade'
ssh mini2 'cd ~/dotfiles && git pull && /opt/homebrew/bin/brew bundle --file=~/dotfiles/Brewfile --no-upgrade'

# 3. locally
brew bundle --file=~/dotfiles/Brewfile --no-upgrade && source ~/.zshrc
```

Step 2 runs `brew bundle` directly rather than full `bootstrap.sh`, on purpose: it's the identical
command from `macos.sh:38`, but full bootstrap also rewrites macOS defaults, `killall`s Dock/Finder,
and runs `mas install` for Xcode/KakaoTalk — disruptive on a box you're not sitting at.
`bootstrap.sh` stays the from-scratch path for a new machine.

`~/.zshrc` is already a dotbot symlink on both minis, so `git pull` alone updates their shell config.

---

## Layer 3 — HEAD mosh for the clipboard-drop bug (all three machines)

**Symptom.** Drag-select text in a remote tmux (e.g. inside a Claude Code pane) — it copies on the
mini but pasting on the MacBook gives *stale* text, or nothing new. It "seemed fixed" before and
came back. It is neither tmux nor Ghostty nor the Aug-31 OSC 52 override; all of those pass the
escape through correctly.

**Root cause — mosh 1.4.0.** mosh only forwards an OSC 52 clipboard write when its *content* differs
from the last one it sent. In `src/terminal/terminaldisplay.cc`:

```c
/* has clipboard changed? */
if ( f.get_clipboard() != frame.last_frame.get_clipboard() ) {
  frame.append( "\033]52;c;" );
```

So copying the same text twice — or copying text equal to what mosh last sent — is silently dropped.
Meanwhile the *local* clipboard has moved on to something else, so the paste is stale. The bug only
bites when a repeat lines up with a local clipboard change, which is why it comes and goes.

**Reproduced 2026-09-14** on mini2: (1) copy `SAME_TEXT_TWICE` through mosh → lands on the Mac;
(2) overwrite the Mac clipboard locally with `OTHER`; (3) copy the identical `SAME_TEXT_TWICE`
again → clipboard stays `OTHER`, the repeat is eaten; (4) copy a different string → lands
immediately. The pipe is healthy; only exact repeats get dropped.

**Fix — upstream, HEAD only.** mosh replaced the content compare with a per-copy counter (an 8-bit
sequence number bumped on every copy), so duplicates go through: `mosh#1104`, fixing `mosh#1090`.
Not in the 1.4.0 release. Cross-referenced by `claude-code#74214`. The `Brewfile` now pins
`brew "mosh", args: ["HEAD"]`.

### Two things `brew bundle` will *not* do for you

1. **It won't replace an installed release build with HEAD.** `brew bundle` sees mosh present and
   moves on. The swap has to be explicit (`uninstall` then `install --HEAD`), so the Layer-1
   `brew bundle --no-upgrade` rollout step does *not* cover this.
2. **Uninstalling mosh triggers `autoremove`**, which took `go` off mini2 during an earlier revert
   (see Open item). Guard every uninstall with `HOMEBREW_NO_AUTOREMOVE=1`.

### Rollout

```sh
# ── this Mac first — verify the fix before touching the minis ───────────────
cd ~/dotfiles && git pull        # if the Brewfile change came from elsewhere
HOMEBREW_NO_AUTOREMOVE=1 brew uninstall mosh
brew install --HEAD mosh
mosh --version                   # want a git-describe string, not "mosh 1.4.0"
# Quit + reopen every Ghostty/mosh session: the running client and server stay
# the OLD binary until relaunched. Then re-run the repro above — the repeat lands.

# ── each mini, only after the Mac side checks out ───────────────────────────
for m in mini1 mini2; do
  ssh "$m" 'cd ~/dotfiles && git pull \
    && HOMEBREW_NO_AUTOREMOVE=1 /opt/homebrew/bin/brew uninstall mosh \
    && /opt/homebrew/bin/brew install --HEAD mosh \
    && /opt/homebrew/bin/mosh-server --version'
done
```

**Both ends must run HEAD**, then start a *fresh* session. A HEAD client against a 1.4.0 server (or
the reverse) still negotiates the old behavior; an existing session keeps its old binaries until you
quit and reattach.

**Gotchas.**
- **mini2 was offline** at spec time (`ssh mini2` timed out); run its line when it's reachable.
  mini1 answered fine.
- **HEAD updates rebuild from source.** `brew upgrade` won't bump a `--HEAD` formula without
  `--fetch-HEAD`, and it compiles rather than pouring a bottle — a few minutes. Fine for a
  rarely-touched tool.
- **When the fix ships in a tagged release**, drop `args: ["HEAD"]` back to plain `brew "mosh"` and
  reinstall to return to bottles.

**Workaround without upgrading:** hold Shift while dragging. Ghostty does its own selection and
`copy-on-select = clipboard` copies locally, bypassing mosh and tmux entirely.

---

## Layer 2 — mini2's Wi-Fi (mini2, at home only)

**mini1 is excluded** — different location, so its latency is internet distance. Layer 1 is its whole
fix.

**This is a latency problem, not a bandwidth problem.** A terminal needs consistency, not throughput:
50 Mbps at a steady 3ms beats 86 Mbps at 45ms jitter. Ordered by cost:

1. **Free, do first — try 2.4GHz.** mini2 is on `U+NetD694_5G` (channel 36). 5GHz degrades badly
   through walls; the 2.4GHz `U+NetD694` (channel 1) penetrates far better at distance. Lower
   ceiling, likely much better stability. Fully reversible.
2. **Free — reposition mini2.** Out of any enclosure, off the floor, clearer line of sight to the
   router. −67 dBm → −55 dBm is realistic from placement alone.
3. **~$50–70 — powerline Ethernet adapter.** The real fix given the cable constraint: a pair
   (e.g. TP-Link AV2000) carries Ethernet over the building's electrical wiring, one unit at the
   router and one at mini2. Throughput drops if the rooms are on different breaker circuits, but
   latency should still beat the current Wi-Fi.
4. **Mesh node / AP near mini2** — only if you already own one; powerline is cheaper for a fixed
   desktop.

---

## Considered and dropped — Tailscale hardening / lockout watchdog

Investigated whether mini2's Tailscale is less robust than mini1's, since a drop while away would
lock you out. **It isn't — the two are configured identically, so there is nothing to match and no
work to do here.**

| | mini1 | mini2 |
|---|---|---|
| Install source | `cask "tailscale-app"` (`Brewfile:40`) | same |
| System extension | `io.tailscale.ipn.macsys.network-extension` | same |
| Login-item helper | not registered | registered |
| Uptime, unattended | **10d 16h, remote, reachable** | 5d 23h |

An earlier read of this as a risk came from checking only `/Library/LaunchDaemons`. Tailscale's cask
does not use that path — it installs a **system extension**, which runs at system level rather than
depending on the login session. mini1's 10-day remote uptime is direct evidence the arrangement
survives long unattended stretches.

Unattended-operation settings are already correct on mini2 as well: `womp 1` (wake on network),
`autorestart 1` (reboot after power loss), `tcpkeepalive 1`, `sleep 0`.

Residual risk is at the Wi-Fi layer, not the Tailscale layer: if mini2's radio drops and does not
auto-rejoin, no Tailscale configuration helps. macOS auto-rejoins known networks by default, and
Layer 2 reduces how often the radio is marginal in the first place. Not worth a watchdog.

---

## Files to modify

| File | Change |
|---|---|
| `Brewfile` | Add `brew "mosh"` |
| `zshrc:80-84` | Replace both aliases with `_remote_mosh`/`_remote_ssh` + 4 aliases |
| `zshrc:98-99`, `111-112` | Keepalives + `ConnectTimeout=15` on `mini1fwd`/`mini2fwd` |
| `zshrc:128`, `148` | Keepalives + `ConnectTimeout=15` on `*send` `ssh_opts` |
| `zshrc:129-130` | Delete `mini1send`'s dead `192.168.219.46` LAN probe |

Not touched: `bootstrap.sh`, `macos.sh` (no change needed), `~/.ssh/config` (untracked), `.zshenv` on
either mini, the router, and the SSH transport for `*fwd`/`*send`.

## Verification

1. **Baseline first**, for comparison:
   ```sh
   ping -c 60 -i 1 100.119.210.87 | tail -2    # mini2: currently avg ~45ms, max ~184ms
   ping -c 60 -i 1 100.122.37.52  | tail -2    # mini1: currently avg ~54ms, max ~120ms
   ssh mini2 'system_profiler SPAirPortDataType | grep -E "Signal|Transmit Rate"'
   ```
2. **Reproducible, not hand-installed** —
   `ssh mini1 '/opt/homebrew/bin/brew bundle check --file=~/dotfiles/Brewfile'` passes on both minis.
   This is what proves the setup came from the repo.
3. **Both aliases attach** — `mini1` and `mini2` each land in that box's *existing* tmux session
   (mini2 has `implentio`, `implentio-worktrees`, `personal` — not a new one).
4. **Survives a link drop.** With `mini2` attached, from a *second* terminal:
   ```sh
   ssh mini2 'networksetup -setairportpower en1 off; sleep 10; networksetup -setairportpower en1 on'
   ```
   Expected: `[network disconnected]`, then automatic resume, tmux intact, **no manual re-attach**.
5. **Survives *your* network changing — the test that matters for working outside.** With `mini1`
   attached over mosh, switch the MacBook from Wi-Fi to an iPhone hotspot. The session must resume
   on its own. This is the case plain SSH can never pass.
6. **Fallbacks and helpers still work** — `mini2ssh` attaches over plain SSH; `mini2fwd 3000`
   forwards a port; `mini1send`/`mini2send` copy a file and put the path on the clipboard.
   Time `mini1send` before and after: it should lose the ~5s LAN-probe stall.
7. **No orphan buildup** — after a few days, `ssh mini2 'pgrep -fl mosh-server'` shows at most one
   per active session.
8. **Layer 2 measured** — re-run step 1 after the 2.4GHz switch or powerline install. Target for
   mini2 at home: avg under 10ms, max under 40ms.

## Open item

`go` on mini2 is 1.26.6; it was 1.24.5 before an earlier revert (Homebrew's `autoremove` took it as
collateral, and no cached 1.24.5 bottle existed). Note `brew install go@1.24` is keg-only and would
not be linked into `PATH` the way the original was.

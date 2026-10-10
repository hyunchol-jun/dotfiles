# hive mod — next two features

Date: 2026-10-10. Owner: Joseph. Mod lives at `~/.claude/mods/hive` (not in the stack repo).
Baseline: `claude plugin validate . && claude plugin test .` green on Claude Code 2.1.296.

Status 2026-10-10: S done and committed. E built then removed (restorable). B dropped. Roadmap empty.
Only candidate with teeth: a `tool.call` guard refusing prod writes, which would need E's probe back.

---

## S. Share-ready standalone — no repo change, no marketplace, no nix — DONE 2026-10-10

Shareable unit = this folder. Someone clones it and runs Claude Code with `--plugin-dir`.
Home = `~/dotfiles/.claude/mods/hive`, linked to `~/.claude/mods` by dotbot, so every machine
that runs `./install` gets it. Not its own git repo.

1. `bin/hive`: bash launcher (not zsh functions). Terminal tint best-effort: tmux if `$TMUX`,
   OSC 11 otherwise, never fails, never blocks launch.
2. `apiaryos.mcp.json` moves into this folder; `bin/hive` references it relative to itself.
   Still the only place apiaryos is defined.
3. Unset `APIARY_CAPTURE_DISABLED` == plain; the mod pins it to 1 via `$.env.set` so capture.sh
   sees it. Only `hive` sets 0. The one-line `claude()` rc function STAYS: without a marketplace
   install nothing else loads the mod (deny + prompt note) in a plain session.
4. `README.md`: what/why, plain vs hive, install (clone, PATH, one-time Authentik login),
   platform table, "later: marketplace + nix" pointer.
5. Move into dotfiles: `~/dotfiles/.claude/mods/hive`; add `~/.claude/mods: .claude/mods` to
   `install.conf.yaml`; `bin` on PATH via one `zshrc` line; `.gitignore` the generated
   `.claude-plugin/types/`. Commit to dotfiles (no secrets in the folder).
   Per-machine manual steps (README): Authentik OAuth login once, `/plugin install apiary-capture`.

### Constraints this puts on E and B
- **No tool the host may lack.** No `lsof`, no `ss`, no `getopt` quirks. Port probes = Node
  `net.connect` from inside the mod. Process args = `ps -o args` (mac + Linux).
- **No hardcoded paths to the stack repo.** Anything that depends on it (tunnel env file prefix,
  kube context names, brand SQL) goes in `hive.config.json` at the mod root with defaults that
  match Implentio today. `/config` rows expose the same values. A sharer edits one file.
- **Degrade, don't fail.** Missing kubectl, no tunnel, no `ps`: the row shows `?`, context line
  omits it, tests cover each absence.
- **Secrets never in the mod.** Tunnel creds are read from the env file the repo skill writes,
  in-process, never logged, never injected. The mod itself ships no credentials.
- **Linux capture works.** capture.sh reads the token from Secret Service (`secret-tool`) on Linux
  and a DPAPI file on Windows. Verified in its source, not on a Linux box.

---

## E. Environment tint — BUILT then REMOVED 2026-10-10 (restorable: dotfiles commit 62d07f5)

Removed because it only mirrors state and enforces nothing; the user judged the benefit too small
without the `tool.call` guard (E2) or B using the verdict. Re-apply with `git revert` of the removal
commit or cherry-pick 62d07f5 if either lands.

### Why
`.env` tunnel targets flip-flop between PROD and DEV (memory: local-apiv2-points-at-prod).
Today the only check is a manual one each session. Make it a band, red for prod.

### Signals (all local, no network)
| Signal | How | Meaning |
|---|---|---|
| DB tunnel | glob `/tmp/implentio-db-{development,production}.env` | env in filename; file is deleted on tunnel exit |
| kube context | `$.process.run(["kubectl","config","current-context"])` | `production-primary` / `development-primary` |
| Trino pf | `bash -c 'exec 3<>/dev/tcp/127.0.0.1/40080'` via `$.process.run` (the mod has no Node) | port-forward alive (memory: it wedges silently; alive ≠ healthy) |
| api-v2 :9001 | same /dev/tcp probe + `ps -axo args` grep for the forwarder | the flip-flopping one; argv has the far end |

All four come from `hive.config.json` (`tunnelEnvDir`, `tunnelEnvPrefix`, `prodWords`, `devWords`, `ports`, `pollMs`), defaults = Implentio.

Lessons: `$` may only be passed to top-level functions (validator rule); the validator's scanner is esbuild, so a real parse error shows up as nonsense line numbers; `$.plugin.root` gives the mod folder.

Out of scope v1: Vault token env (dev vs prod), Snowflake role. Add later as rows.

### Behaviour
- Poll every 15s with `$.clock.every`. Skip when terminal unfocused if API exposes it; else just poll.
- Band row 2 (below the hive/plain row): `DB ● prod ro :51003 · kube production-primary · trino :40080 · 9001 → prod`.
- Colour: red if ANY signal says prod, green if all dev, grey if none. Hive amber stays on row 1.
- `prompt.context`: inject one line, e.g. `Local tunnels: DB=production (read-only), kube=production-primary.`
  so the model stops asking "is this prod?" and stops assuming dev.
- `/env` command prints the same table with timestamps of last check.

### Tests (`hooks/hive.test.ts`)
- fake `/tmp` dir with prod env file → red, context line says production
- no files, dev kube ctx → green
- both prod + dev files → red, both listed
- `$.process.run` failing (no kubectl) → row shows `kube ?`, never throws
- no `ps` → 9001 row shows `:9001 listening, far end ?`
- config file missing → defaults apply; malformed → one warning toast, defaults apply

### Done when
- Open a prod tunnel via `connect-implentio-db production`, band turns red within 15s, closes → grey.
- Tests green, validate green.

Effort: an afternoon.

---

## B. Brand context pane — DROPPED 2026-10-10

apiaryOs already exposes every fact B would show (`brand_get`, `brand_flag_summary`,
`workflow_latest_for_brand`, `credit_memo_list`, `invoice_lifecycle_list`, `db_query`), one call each
in a hive session. Plain sessions have the `implentio-db` skill. A pane re-fetching the same over a
tunnel is a worse copy. Original design kept below for reference.

### Original design

### Why
Every brand investigation re-derives the same facts: storeType, flags, last recon, lake sync lag,
open credit memos. Half the memory files exist because of that. Fetch once, show it, inject it.

### Data source
Decide at start (first 20 min): **Postgres via the existing read-only tunnel** vs **api-v2 HTTP**.
Recommendation: Postgres over the tunnel. No auth story to build, the tunnel is already the
sanctioned read-only path, and E already knows the port. api-v2 would need a session cookie.
Needs E's tunnel detection; if no tunnel, pane says "open a DB tunnel first" and the command
offers to run `connect-implentio-db <env>`.

### Facts v1 (one query each, all `WHERE brand_id = $1`)
| Row | Source |
|---|---|
| id, legacy id, slug, status | `client.brand` |
| flags (READ_ICEBERG_CDM etc.) | `client.brand_flag` |
| storeType hint | derived from READ_ICEBERG_CDM flag |
| last recon run (status, started, invoice count) | `cdm.reconciliation_run` latest |
| last brand_rule change vs lake snapshot | `cdm.brand_rule` max(updated_at) vs `iceberg brand_rule$snapshots` — **v2**, needs Trino |
| open credit memos (count, newest) | credit memo table (confirm name during build) |
| billers | distinct biller from `cdm.logistics_invoice` |

Exact table/column names: verify during build with the `implentio-db` skill, do not trust this list.
SQL lives in `queries/brand/*.sql` inside the mod, one file per row, read-only, `$1` = brand id.
A sharer with a different schema swaps files, not code.

Dependency on the stack repo: the tunnel itself (`connect-implentio-db`) is a repo skill. The mod
does not create tunnels; it only detects one via the env file. README states this as a prereq.

### Behaviour
- `/brand qure` → resolves slug or UUID, opens a `Pane` titled `🏷 qure`, rows as above, refresh
  button + 60s auto-refresh while open. `/brand` with no arg closes it.
- `prompt.context` gets a compact block (≤ 12 lines) while a brand is pinned:
  `Pinned brand: qure (946). storeType=iceberg. Flags: READ_ICEBERG_CDM. Last recon: SUCCESS 2026-10-09 (12 invoices). ...`
- Pin survives compaction (re-inject on `session.compact`).
- Band row 1 gets `· 🏷 qure` while pinned so it's visible even with the pane closed.

### Guardrails
- Read-only: queries go through the ro tunnel only. Mod never holds write creds.
- Env-aware: pane header shows PROD/DEV from E; prod rows red-tinted.
- Secrets: read `PASSWORD` from the env file in-process, never echo it, never put it in context.

### Tests
- slug resolve, UUID resolve, unknown brand → pane shows "not found", nothing injected
- no tunnel → helpful pane, nothing injected
- context block byte-limit (≤ 12 lines, ≤ 1.5 KB)
- compaction re-inject

### Done when
- `/brand qure` on the dev tunnel shows real rows; asking "what storeType is this brand" is
  answered from the injected block without a tool call.

Effort: 1 day after E.

---

## Open questions (answer before B)
1. Postgres-over-tunnel or api-v2 HTTP? (recommendation above: tunnel)
2. Should the pinned brand also scope `tool.call` warnings, e.g. warn when a SQL string mentions a
   different brand_id? Tempting, out of scope for v1.
3. Ship the mod in the repo under `tools/claude-plugins/hive` once E+B land? Blocks on the Slack
   question from today's post. Until then: standalone folder, `--plugin-dir`, see S.

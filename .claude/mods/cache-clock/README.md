# cache-clock

Shows how long the prompt cache stays warm after the last model request, warns before it
lapses, and flags a cache miss. Loaded in every session through `CLAUDE_CODE_PLUGIN_DIRS`
in `~/.claude/settings.json` (`env` block), so `claude`, `cc`, `ccfh` and `hive` all get it.

- Status line: `cache 42m` → `cache 4m30s left ⚠` → `cache COLD (…)`.
- Band above the prompt in the last `warnMinutes`, and for 3 min after a miss.
- Miss = a request writes ≥ `missTokens` and reads under half the prefix the last request left.
  A full write the clock predicted is a cold write, never a miss: first request, TTL lapsed,
  after compaction, after a model or effort switch, after `/clear` or `/resume`.
- Miss toast blames the prefix (CLAUDE.md, MCP tools, system prompt) under 5m, else the TTL may have dropped to 5m.
- `/cache`: time left, last request hit / MISS / cold write (with reason), read/wrote/uncached tokens.
- `/config` rows: ttlMinutes (60), warnMinutes (5), missTokens (20000).

Develop: `command claude plugin validate . && command claude plugin test .`
(load the `plugin-authoring` skill once per build to regenerate `.claude-plugin/types/`).

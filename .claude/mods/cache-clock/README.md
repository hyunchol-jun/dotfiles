# cache-clock

Shows how long the prompt cache stays warm after the last model request, warns before it
lapses, and flags a cache miss. Loaded in every session through `CLAUDE_CODE_PLUGIN_DIRS`
in `~/.claude/settings.json` (`env` block), so `claude`, `cc`, `ccfh` and `hive` all get it.

- Status line: `cache 42m` → `cache 4m30s left ⚠` → `cache COLD (…)`.
- Band above the prompt in the last `warnMinutes`, and for 3 min after a miss.
- `/cache`: time left, last request hit/miss, read/wrote/uncached tokens.
- `/config` rows: ttlMinutes (60), warnMinutes (5), missTokens (20000).

Develop: `command claude plugin validate . && command claude plugin test .`
(load the `plugin-authoring` skill once per build to regenerate `.claude-plugin/types/`).

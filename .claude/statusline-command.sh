#!/usr/bin/env bash
# Status line for Claude Code, mirroring the oh-my-posh prompt style.
# Reads JSON from stdin and outputs a single status line.

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# -- Path segment (blue) --
path_segment=""
if [ -n "$cwd" ]; then
  path_segment="\033[34m${cwd}\033[0m"
fi

# -- Git segment (grey + cyan for ahead/behind) --
git_segment=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  dirty=""
  if ! git -C "$cwd" --no-optional-locks diff --quiet 2>/dev/null \
     || ! git -C "$cwd" --no-optional-locks diff --cached --quiet 2>/dev/null; then
    dirty="*"
  fi
  ahead_behind=""
  upstream=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  if [ -n "$upstream" ]; then
    ahead=$(git -C "$cwd" --no-optional-locks rev-list --count "${upstream}..HEAD" 2>/dev/null)
    behind=$(git -C "$cwd" --no-optional-locks rev-list --count "HEAD..${upstream}" 2>/dev/null)
    [ "${behind:-0}" -gt 0 ] 2>/dev/null && ahead_behind="${ahead_behind}\033[36m⇣\033[0m"
    [ "${ahead:-0}" -gt 0 ] 2>/dev/null && ahead_behind="${ahead_behind}\033[36m⇡\033[0m"
  fi
  git_segment=" \033[2m${branch}${dirty}\033[0m${ahead_behind}"
fi

# -- Model segment (dimmed) --
model_segment=""
if [ -n "$model" ]; then
  model_segment=" \033[2m${model}\033[0m"
fi

# -- Context segment (yellow when high usage) --
ctx_segment=""
if [ -n "$used_pct" ]; then
  used_int=${used_pct%.*}
  if [ "${used_int:-0}" -ge 75 ] 2>/dev/null; then
    ctx_segment=" \033[33m${used_pct}%\033[0m"
  else
    ctx_segment=" \033[2m${used_pct}%\033[0m"
  fi
fi

printf '%b\n' "${path_segment}${git_segment}${model_segment}${ctx_segment}"

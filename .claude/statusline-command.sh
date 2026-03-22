#!/usr/bin/env bash
# Status line for Claude Code, mirroring the oh-my-posh prompt style.
# Reads JSON from stdin and outputs a single status line.

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
rate_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rate_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rate_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Convert epoch timestamp to relative time string (e.g. "2h13m", "4d3h")
format_remaining() {
  local reset_epoch="$1"
  [ -z "$reset_epoch" ] && return
  local now diff
  now=$(date +%s)
  diff=$((reset_epoch - now))
  [ "$diff" -le 0 ] && echo "now" && return
  local days=$((diff / 86400)) hrs=$(( (diff % 86400) / 3600 )) mins=$(( (diff % 3600) / 60 ))
  local result=""
  [ "$days" -gt 0 ] && result="${days}d"
  [ "$hrs" -gt 0 ] && result="${result}${hrs}h"
  if [ "$days" -eq 0 ] && [ "$mins" -gt 0 ]; then
    result="${result}${mins}m"
  fi
  [ -z "$result" ] && result="now"
  echo "$result"
}

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

# -- Rate limits segment (red ≥90%, yellow ≥75%, dimmed otherwise) --
rate_segment=""
if [ -n "$rate_5h" ]; then
  rate_5h_int=${rate_5h%.*}
  remaining_5h=$(format_remaining "$rate_5h_reset")
  rate_5h_label="5h: ${rate_5h}%"
  [ -n "$remaining_5h" ] && rate_5h_label="5h: ${rate_5h}% (${remaining_5h})"
  if [ "${rate_5h_int:-0}" -ge 90 ] 2>/dev/null; then
    rate_segment=" \033[31m${rate_5h_label}\033[0m"
  elif [ "${rate_5h_int:-0}" -ge 75 ] 2>/dev/null; then
    rate_segment=" \033[33m${rate_5h_label}\033[0m"
  else
    rate_segment=" \033[2m${rate_5h_label}\033[0m"
  fi
fi
if [ -n "$rate_7d" ]; then
  rate_7d_int=${rate_7d%.*}
  remaining_7d=$(format_remaining "$rate_7d_reset")
  rate_7d_label="7d: ${rate_7d}%"
  [ -n "$remaining_7d" ] && rate_7d_label="7d: ${rate_7d}% (${remaining_7d})"
  if [ "${rate_7d_int:-0}" -ge 90 ] 2>/dev/null; then
    rate_segment="${rate_segment} \033[31m${rate_7d_label}\033[0m"
  elif [ "${rate_7d_int:-0}" -ge 75 ] 2>/dev/null; then
    rate_segment="${rate_segment} \033[33m${rate_7d_label}\033[0m"
  else
    rate_segment="${rate_segment} \033[2m${rate_7d_label}\033[0m"
  fi
fi

printf '%b\n' "${path_segment}${git_segment}${model_segment}${ctx_segment}${rate_segment}"

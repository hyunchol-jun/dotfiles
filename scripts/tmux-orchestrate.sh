#!/opt/homebrew/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config/tmux-sessions"

# --- Usage ---
usage() {
  echo "Usage: tmo <config-name> [--no-attach] [--force] [--kill]"
  echo ""
  echo "  config-name   Name of YAML file in config/tmux-sessions/ (without .yml)"
  echo "  --no-attach   Don't attach to session after creation"
  echo "  --force       Kill existing session if it exists"
  echo "  --kill        Kill the session and exit"
  exit 1
}

# --- Args ---
[[ $# -lt 1 ]] && usage

CONFIG_NAME="$1"
shift

NO_ATTACH=false
FORCE=false
KILL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-attach) NO_ATTACH=true ;;
    --force) FORCE=true ;;
    --kill) KILL=true ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
  shift
done

CONFIG_FILE="$CONFIG_DIR/${CONFIG_NAME}.yml"

# --- Kill mode ---
if $KILL; then
  if ! command -v yq &>/dev/null; then
    # Fall back to config name as session name
    SESSION="$CONFIG_NAME"
  elif [[ -f "$CONFIG_FILE" ]]; then
    SESSION=$(yq -r '.name' "$CONFIG_FILE")
  else
    SESSION="$CONFIG_NAME"
  fi
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux kill-session -t "$SESSION"
    echo "Killed session '$SESSION'"
  else
    echo "No session '$SESSION' found"
  fi
  exit 0
fi

# --- Preflight checks ---
if ! command -v yq &>/dev/null; then
  echo "Error: yq is not installed. Run: brew install yq"
  exit 1
fi

if ! command -v tmux &>/dev/null; then
  echo "Error: tmux is not installed. Run: brew install tmux"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config not found: $CONFIG_FILE"
  echo "Available configs:"
  ls "$CONFIG_DIR"/*.yml 2>/dev/null | xargs -I{} basename {} .yml | sed 's/^/  /'
  exit 1
fi

# --- Phase A: Parse config ---
SESSION_NAME=$(yq -r '.name' "$CONFIG_FILE")
DEFAULT_TIMEOUT=$(yq '.default_timeout // 120' "$CONFIG_FILE")
POLL_INTERVAL=$(yq '.poll_interval // 2' "$CONFIG_FILE")
WINDOW_NAME=$(yq -r '.windows[0].name' "$CONFIG_FILE")
LAYOUT=$(yq -r '.windows[0].layout // "tiled"' "$CONFIG_FILE")
PANE_COUNT=$(yq '.windows[0].panes | length' "$CONFIG_FILE")

declare -a PANE_IDS
declare -A PANE_ROOT PANE_CMD PANE_READY PANE_DEPENDS PANE_TIMEOUT

for ((i = 0; i < PANE_COUNT; i++)); do
  id=$(yq -r ".windows[0].panes[$i].id" "$CONFIG_FILE")
  PANE_IDS+=("$id")
  PANE_ROOT[$id]=$(yq -r ".windows[0].panes[$i].root" "$CONFIG_FILE")
  PANE_CMD[$id]=$(yq -r ".windows[0].panes[$i].command" "$CONFIG_FILE")
  PANE_READY[$id]=$(yq -r ".windows[0].panes[$i].ready_when // \"\"" "$CONFIG_FILE")
  PANE_TIMEOUT[$id]=$(yq ".windows[0].panes[$i].timeout // $DEFAULT_TIMEOUT" "$CONFIG_FILE")

  # depends_on can be a string or list
  dep_type=$(yq -r ".windows[0].panes[$i].depends_on | type" "$CONFIG_FILE")
  if [[ "$dep_type" == "!!seq" ]]; then
    PANE_DEPENDS[$id]=$(yq -r ".windows[0].panes[$i].depends_on[]" "$CONFIG_FILE" | tr '\n' ' ')
  elif [[ "$dep_type" == "!!str" ]]; then
    PANE_DEPENDS[$id]=$(yq -r ".windows[0].panes[$i].depends_on" "$CONFIG_FILE")
  else
    PANE_DEPENDS[$id]=""
  fi
done

# --- Circular dependency detection ---
detect_cycle() {
  local node="$1"
  local -n visited_ref=$2
  local -n stack_ref=$3

  visited_ref[$node]=1
  stack_ref[$node]=1

  for dep in ${PANE_DEPENDS[$node]:-}; do
    if [[ -z "${visited_ref[$dep]:-}" ]]; then
      if detect_cycle "$dep" visited_ref stack_ref; then
        return 0
      fi
    elif [[ -n "${stack_ref[$dep]:-}" ]]; then
      echo "Error: Circular dependency detected involving '$dep' and '$node'"
      return 0
    fi
  done

  unset "stack_ref[$node]"
  return 1
}

declare -A VISITED STACK
for id in "${PANE_IDS[@]}"; do
  if [[ -z "${VISITED[$id]:-}" ]]; then
    if detect_cycle "$id" VISITED STACK; then
      exit 1
    fi
  fi
done

# Validate that all dependencies reference existing pane IDs
for id in "${PANE_IDS[@]}"; do
  for dep in ${PANE_DEPENDS[$id]:-}; do
    found=false
    for check_id in "${PANE_IDS[@]}"; do
      [[ "$dep" == "$check_id" ]] && found=true && break
    done
    if ! $found; then
      echo "Error: Pane '$id' depends on '$dep', which does not exist"
      exit 1
    fi
  done
done

# --- Handle existing session ---
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  if $FORCE; then
    echo "Killing existing session '$SESSION_NAME'..."
    tmux kill-session -t "$SESSION_NAME"
  else
    echo "Error: Session '$SESSION_NAME' already exists."
    echo "  Use --force to kill and recreate, or attach with: tmux attach -t $SESSION_NAME"
    exit 1
  fi
fi

# --- Phase B: Create tmux session + panes ---
echo "Creating session '$SESSION_NAME' with window '$WINDOW_NAME'..."

tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME"

for ((i = 1; i < PANE_COUNT; i++)); do
  tmux split-window -t "$SESSION_NAME:$WINDOW_NAME"
done

tmux select-layout -t "$SESSION_NAME:$WINDOW_NAME" "$LAYOUT"

# Map pane indices to logical IDs
declare -A PANE_TMUX_ID
pane_indices=($(tmux list-panes -t "$SESSION_NAME:$WINDOW_NAME" -F '#{pane_index}'))
for ((i = 0; i < PANE_COUNT; i++)); do
  PANE_TMUX_ID[${PANE_IDS[$i]}]="$SESSION_NAME:$WINDOW_NAME.${pane_indices[$i]}"
done

# --- Phase C: Navigate to directories ---
echo "Navigating panes to directories (waiting for direnv)..."
for id in "${PANE_IDS[@]}"; do
  root="${PANE_ROOT[$id]}"
  tmux send-keys -t "${PANE_TMUX_ID[$id]}" "cd $root" Enter
done

sleep 5

# --- Phase D: Dependency-ordered execution ---
declare -A READY_SET STARTED_SET START_TIME

all_started() {
  for id in "${PANE_IDS[@]}"; do
    [[ -z "${STARTED_SET[$id]:-}" ]] && return 1
  done
  return 0
}

all_ready() {
  for id in "${PANE_IDS[@]}"; do
    [[ -z "${READY_SET[$id]:-}" ]] && return 1
  done
  return 0
}

deps_ready() {
  local id="$1"
  for dep in ${PANE_DEPENDS[$id]:-}; do
    [[ -z "${READY_SET[$dep]:-}" ]] && return 1
  done
  return 0
}

echo "Starting panes in dependency order..."

while ! all_started || ! all_ready; do
  # Start panes whose dependencies are met
  for id in "${PANE_IDS[@]}"; do
    if [[ -z "${STARTED_SET[$id]:-}" ]] && deps_ready "$id"; then
      echo "  Starting: $id"
      tmux send-keys -t "${PANE_TMUX_ID[$id]}" "${PANE_CMD[$id]}" Enter
      STARTED_SET[$id]=1
      START_TIME[$id]=$SECONDS

      # If no ready_when, mark ready immediately
      if [[ -z "${PANE_READY[$id]}" ]]; then
        READY_SET[$id]=1
        echo "  Ready: $id (no readiness check)"
      fi
    fi
  done

  # Check readiness of started-but-not-ready panes
  for id in "${PANE_IDS[@]}"; do
    if [[ -n "${STARTED_SET[$id]:-}" && -z "${READY_SET[$id]:-}" ]]; then
      ready_string="${PANE_READY[$id]}"
      output=$(tmux capture-pane -t "${PANE_TMUX_ID[$id]}" -p -S -200 2>/dev/null || true)
      if echo "$output" | grep -qF "$ready_string"; then
        READY_SET[$id]=1
        echo "  Ready: $id (matched: \"$ready_string\")"
      fi

      # Check timeout
      elapsed=$(( SECONDS - START_TIME[$id] ))
      timeout="${PANE_TIMEOUT[$id]}"
      if (( elapsed > timeout )); then
        echo ""
        echo "Error: Pane '$id' timed out after ${timeout}s"
        echo "  Expected to see: \"$ready_string\""
        echo "  Session left running for debugging: tmux attach -t $SESSION_NAME"
        exit 1
      fi
    fi
  done

  # Exit early if everything is done
  all_started && all_ready && break

  sleep "$POLL_INTERVAL"
done

echo ""
echo "All panes started and ready!"

# --- Phase E: Attach ---
if ! $NO_ATTACH; then
  tmux attach-session -t "$SESSION_NAME"
fi

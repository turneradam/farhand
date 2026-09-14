#!/usr/bin/env bash
# farhand watcher: starts jobs in the background and keeps track of them.
# Usage: watcher.sh start <engine> <job>
#        watcher.sh status
set -u

# --- state ------------------------------------------------------------------
# One file per fact, under XDG state. job.pid is the only link between a
# running calculation and any future watcher process.

STATE="${FARHAND_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/farhand}"
LAUNCH="${FARHAND_LAUNCH:-$(dirname "$0")/../launch/launch.sh}"
mkdir -p "$STATE"

# --- helpers ----------------------------------------------------------------

# alive <pid>: exit 0 if the process exists. kill -0 sends no signal; it only
# asks the kernel whether the PID is there.
alive() {
  kill -0 "$1" 2>/dev/null
}

# --- commands ---------------------------------------------------------------

start() {
  local engine="$1" job="$2"

  if [ -f "$STATE/job.pid" ] && alive "$(cat "$STATE/job.pid")"; then
    echo "watcher: busy, job $(cat "$STATE/job.name") is running" >&2
    return 1
  fi

  bash "$LAUNCH" "$engine" "$job" > "$STATE/launch.log" 2>&1 &
  echo "$!" > "$STATE/job.pid"
  echo "$job" > "$STATE/job.name"
  echo "started $job (pid $!)"
}

status() {
  local pid

  if [ ! -f "$STATE/job.pid" ]; then
    echo idle
    return 0
  fi

  pid="$(cat "$STATE/job.pid")"
  if alive "$pid"; then
    echo "running $(cat "$STATE/job.name") (pid $pid)"
  else
    echo "stale: $(cat "$STATE/job.name") (pid $pid) is gone"
  fi
}

case "${1:-}" in
  start)  start "${2:?usage: watcher.sh start <engine> <job>}" \
                "${3:?usage: watcher.sh start <engine> <job>}" ;;
  status) status ;;
  *) echo "usage: watcher.sh {start <engine> <job>|status}" >&2; exit 2 ;;
esac

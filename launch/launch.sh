#!/usr/bin/env bash
# Run a configured engine's job: look up how, pin it, capture output, check
# whether it actually succeeded.
# Usage: launch.sh <engine> <job>
set -u

CONF="${FARHAND_ENGINES_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/farhand/engines.conf}"
ENGINE="${1:?usage: launch.sh <engine> <job>}"
JOB="${2:?usage: launch.sh <engine> <job>}"

if [ ! -f "$CONF" ]; then
  echo "launch: no config at $CONF" >&2
  exit 2
fi

engine_conf() {
  local want="$1" key="$2"
  local section="" line k v

  while read -r line; do
    case "$line" in
      '['*']')
        section="${line#[}"
        section="${section%]}"
        continue
        ;;
      ''|'#'*) continue ;;
    esac

    [ "$section" = "$want" ] || continue

    k="${line%%=*}"
    v="${line#*=}"
    k="$(printf '%s' "$k" | tr -d '[:space:]')"
    v="${v# }"

    if [ "$k" = "$key" ]; then
      printf '%s\n' "$v"
      return 0
    fi
  done < "$CONF"

  return 1
}

# state helper
set_state() {
  printf '%s\n' "$2" > "$1.tmp" && mv "$1.tmp" "$1"
}

pin="$(engine_conf "$ENGINE" pin)"    || { echo "launch: no pin for $ENGINE" >&2; exit 2; }
run="$(engine_conf "$ENGINE" run)"    || { echo "launch: no run for $ENGINE" >&2; exit 2; }
ok="$(engine_conf "$ENGINE" ok)"      || ok="exit0"

run="${run//__JOB__/$JOB}"
LOG="run.log"

echo "launch: engine=$ENGINE job=$JOB pin=$pin" >&2
echo "launch: $run" >&2

# Job directory handling
WORK="${FARHAND_WORK:-$PWD}"
JOBDIR="$WORK/$JOB"

if [ ! -d "$JOBDIR" ]; then
  echo "launch: no job directory $JOBDIR" >&2
  exit 2
fi

cd "$JOBDIR" || { echo "launch: cannot enter $JOBDIR" >&2; exit 2; }

set_state status running
date -u +%Y-%m-%dT%H:%M:%SZ > started

taskset -c "$pin" bash -c "$run" > "$LOG" 2>&1
rc=$?

date -u +%Y-%m-%dT%H:%M:%SZ > finished
set_state rc "$rc"

if [ "$ok" = "exit0" ]; then
  if [ "$rc" -eq 0 ]; then
    result="done"
  else
    result="failed"
  fi
else
  if bash -c "$ok" >/dev/null 2>&1; then
    result="done"
  else
    result="failed"
  fi
fi

set_state status "$result"

echo "launch: exit=$rc result=$result" >&2
[ "$result" = "done" ]

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
  ... as above ...
}

pin="$(engine_conf "$ENGINE" pin)"    || { echo "launch: no pin for $ENGINE" >&2; exit 2; }
run="$(engine_conf "$ENGINE" run)"    || { echo "launch: no run for $ENGINE" >&2; exit 2; }
ok="$(engine_conf "$ENGINE" ok)"      || ok="exit0"

run="${run//__JOB__/$JOB}"
LOG="run.log"

echo "launch: engine=$ENGINE job=$JOB pin=$pin" >&2
echo "launch: $run" >&2

taskset -c "$pin" bash -c "$run" > "$LOG" 2>&1
rc=$?

if [ "$ok" = "exit0" ]; then
  [ "$rc" -eq 0 ] && result=done || result=failed
else
  bash -c "$ok" >/dev/null 2>&1 && result=done || result=failed
fi

echo "launch: exit=$rc result=$result" >&2
[ "$result" = "done" ]

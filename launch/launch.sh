#!/usr/bin/env bash
# Run a configured engine's job: look up how, pin it, capture output, check
# whether it actually succeeded.
# Usage: launch.sh <engine> <job>
set -u

# --- inputs -----------------------------------------------------------------
# Config path follows the XDG convention, overridable so tests can point
# elsewhere. Both arguments are required; a missing one is a usage error.

CONF="${FARHAND_ENGINES_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/farhand/engines.conf}"
ENGINE="${1:?usage: launch.sh <engine> <job>}"
JOB="${2:?usage: launch.sh <engine> <job>}"

if [ ! -f "$CONF" ]; then
  echo "launch: no config at $CONF" >&2
  exit 2
fi

# --- config parser ----------------------------------------------------------
# engine_conf <section> <key> prints the value and returns 0, or returns 1 if
# the section or the key is absent. Splits each line at the FIRST '=' only, so
# a value may itself contain '=' (e.g. a command setting an env var).

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

# --- state helper -----------------------------------------------------------
# Write a state file atomically: to a temp file, then rename over the target.
# A reader (the watcher, the bot) must never catch a half-written file, and a
# plain '>' leaves the file empty for an instant while it truncates.

set_state() {
  printf '%s\n' "$2" > "$1.tmp" && mv "$1.tmp" "$1"
}

# --- what to run ------------------------------------------------------------
# Resolve everything about the engine before touching the filesystem, so an
# unknown engine fails before any job state is created. 'ok' is optional and
# defaults to trusting the exit code.

pin="$(engine_conf "$ENGINE" pin)" || { echo "launch: no pin for $ENGINE" >&2; exit 2; }
run="$(engine_conf "$ENGINE" run)" || { echo "launch: no run for $ENGINE" >&2; exit 2; }
ok="$(engine_conf "$ENGINE" ok)"   || ok="exit0"

run="${run//__JOB__/$JOB}"
LOG="run.log"

# --- where to run -----------------------------------------------------------
# One directory per job: its inputs, its log, its state files. Refuse to create
# it -- a missing job directory is nearly always a typo in the job name, and
# inventing an empty one turns a clear error into a cryptic engine failure.

WORK="${FARHAND_WORK:-$PWD}"
JOBDIR="$WORK/$JOB"

if [ ! -d "$JOBDIR" ]; then
  echo "launch: no job directory $JOBDIR" >&2
  exit 2
fi

cd "$JOBDIR" || { echo "launch: cannot enter $JOBDIR" >&2; exit 2; }

# --- run --------------------------------------------------------------------
# Pinned, because an MPI job advances at the pace of its slowest rank: a single
# rank scheduled onto an efficiency core drags the whole calculation down to
# that core's speed. rc must be captured immediately after the job -- any other
# command in between would overwrite $?.

echo "launch: engine=$ENGINE job=$JOB pin=$pin" >&2
echo "launch: $run" >&2

set_state status running
date -u +%Y-%m-%dT%H:%M:%SZ > started

taskset -c "$pin" bash -c "$run" > "$LOG" 2>&1
rc=$?

date -u +%Y-%m-%dT%H:%M:%SZ > finished
set_state rc "$rc"

# --- did it work? -----------------------------------------------------------
# Exit codes cannot be trusted across scientific codes: some exit 0 having
# crashed, some report success only in their log, some require parsing results.
# 'ok = exit0' trusts the exit code; anything else is a command run here in the
# job directory and judged by its own exit status.

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

# --- report -----------------------------------------------------------------
# Status is written before the final test, because the LAST command executed
# sets this script's exit status -- and the watcher branches on it.

set_state status "$result"

echo "launch: exit=$rc result=$result" >&2
[ "$result" = "done" ]

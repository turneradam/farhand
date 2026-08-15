#!/usr/bin/env bash
# farhand resource arbiter. A lease is a file, if the file is present then a lease is held.
# The file's contents indicate the holder of the lease (cpu, gpu, etc.)
set -u


ARENA="${FARHAND_ARENA:-$HOME/.local/state/farhand/arena}"
LOCK="$ARENA/.lock"
mkdir -p "$ARENA"

holder() {
	cat "$ARENA/$1.lease" 2>/dev/null || true
}

tokens() {
  case "$1" in
    qe|orca|raspa) echo "cpu_hi" ;;
    raspa_e)       echo "ecores" ;;
    lammps)        echo "cpu_lo gpu" ;;
    *) echo "unknown engine: $1" >&2; return 2 ;;
  esac
}

acquire() {
  local engine="$1"
  local t who blocked="" need

  need="$(tokens "$engine")" || return 2

  exec 9>"$LOCK"
  flock 9

  for t in $need; do
    who="$(holder "$t")"
    if [ -n "$who" ] && [ "$who" != "$engine" ]; then
      blocked="$t:$who"
      break
    fi
  done

  if [ -n "$blocked" ]; then
    echo "busy ($blocked)"
    return 1
  fi

  for t in $need; do
    echo "$engine" > "$ARENA/$t.lease"
  done
  echo ok
}

release() {
  local engine="$1"
  local t need

  need="$(tokens "$engine")" || return 2

  exec 9>"$LOCK"
  flock 9

  if [ "$(holder "$token")" = "$engine" ]; then
    rm -f "$ARENA/$token.lease"
  fi
  echo released
}

case "${1:-}" in
  holder)  holder  "${2:?usage: arena.sh holder <token>}" ;;
  acquire) acquire "${2:?usage: arena.sh acquire <engine>}" ;;
  release) release "${2:?usage: arena.sh release <engine>}" ;;
  tokens) tokens  "${2:?usage: arena.sh tokens <engine>}" ;;
  *) echo "usage: arena.sh {holder <token>|acquire <engine>|release <engine>}" >&2; exit 2 ;;
esac

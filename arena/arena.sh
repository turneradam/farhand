#!/usr/bin/env bash
# farhand resource arbiter. A lease is a file, if the file is present then a lease is held.
# The file's contents indicate the holder of the lease (cpu, gpu, etc.)
set -u

ARENA="${FARHAND_ARENA:-$HOME/.local/state/farhand/arena}"

holder() {
	cat "$ARENA/$1.lease" 2>/dev/null || true
}

acquire() {
  local engine="$1"
  local token="cpu_hi"
  local who

  who="$(holder "$token")"

  if [ -n "$who" ] && [ "$who" != "$engine" ]; then
    echo "busy ($token:$who)"
    return 1
  fi

  echo "$engine" > "$ARENA/$token.lease"
  echo ok
}

release() {
  local engine="$1"
  local token="cpu_hi"

  if [ "$(holder "$token")" = "$engine" ]; then
    rm -f "$ARENA/$token.lease"
  fi
  echo released
}

case "${1:-}" in
  holder)  holder  "${2:?usage: arena.sh holder <token>}" ;;
  acquire) acquire "${2:?usage: arena.sh acquire <engine>}" ;;
  release) release "${2:?usage: arena.sh release <engine>}" ;;
  *) echo "usage: arena.sh {holder <token>|acquire <engine>|release <engine>}" >&2; exit 2 ;;
esac

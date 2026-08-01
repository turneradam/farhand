#!/usr/bin/env bash
# farhand resource arbiter. A lease is a file, if the file is present then a lease is held.
# The file's contents indicate the holder of the lease (cpu, gpu, etc.)
set -u

ARENA="${FARHAND_ARENA:-$HOME/.local/state/farhand/arena}"

holder() {
	cat "$ARENA/$1.lease" 2>/dev/null || true
}

case "${1:-}" in
	holder) holder "${2:?usage: arena.sh holder <token>}" ;;
	*) echo "usage: arena.sh holder <token>" >&2; exit 2 ;;
esac

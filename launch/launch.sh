#!/usr/bin/env bash
# Run one job pinned to a CPU set, capturing output and
# recording the result
# launch must be executable (chmod +x)
# Usage: launch.sh <pin> <logfile> <command> [args]
set -u

PIN="${1:?usage: launch.sh <pin> <logfile> <command> [args...]}"
LOG="${2:?usage: launch.sh <pin> <logfile> <command> [args...]}"
shift 2

if [ "$#" -eq 0 ]; then
	echo "launch: no command given" >&2
	exit 2
fi

echo "launch: pin=$PIN log=$LOG cmd=$*" >&2

taskset -c "$PIN" "$@" > "$LOG" 2>&1
rc=$?

echo "launch: exit $rc" >&2
exit "$rc"

#!/usr/bin/env bash
# Behavioural tests for arena.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ARENA_SH="$HERE/../arena/arena.sh"

FARHAND_ARENA="$(mktemp -d)"
export FARHAND_ARENA
trap 'rm -rf "$FARHAND_ARENA"' EXIT

pass=0
fail=0

is() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    printf ' ok %s\n' "$1"
  else
    fail=$((fail + 1))
    printf ' FAIL %s (expected %s, got %s)\n' "$1" "$3" "$2"
  fi
}

a() { bash "$ARENA_SH" "$@"; }

echo "arena.sh"

# sequential tests for clearer order and structure, if farhand gets bigger
# will need to isolate each test
is "first acquire is granted"  "$(a acquire qe)"  "ok"
is "shared token blocks"  "$(a acquire orca)"  "busy (cpu_hi:qe)"
is "disjoint token co-runs"  "$(a acquire lammps)"  "ok"
is "second lane co-runs"  "$(a acquire raspa_e)"  "ok"
is "re-acquire by holder"  "$(a acquire qe)"  "ok"
is "tokens lists the sect"  "$(a tokens lammps)"  "cpu_lo gpu"

a acquire orca >/dev/null
is "busy exits 1" "$?" "1"

a tokens nosuch 2>/dev/null
is "unknown engine exits 2" "$?" "2"

# check ownership behavours
a release orca >/dev/null
is "release cannot steal"  "$(a holder cpu_hi)"  "qe"
is "release by holder"    "$(a release lammps)"  "released"
is "multi-token release: gpu"  "$(a holder gpu)"  ""
is "multi-token release: cpu_lo" "$(a holder cpu_lo)"  ""
is "release is idempotent"  "$(a release lammps)"  "released"

# check for all or nothing functionality
rm -f "$FARHAND_ARENA"/*.lease
echo someone_else >"$FARHAND_ARENA/gpu.lease"
is "partial availability refused" "$(a acquire lammps)" "busy (gpu:someone_else)"
is "no token leaked on refusal"   "$(a holder cpu_lo)"  ""

# pass/ fail signaller
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

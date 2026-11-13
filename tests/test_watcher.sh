#!/usr/bin/env bash
# Behavioural tests for watcher.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
WATCHER_SH="$HERE/../watcher/watcher.sh"

TMP="$(mktemp -d)"
FARHAND_STATE="$TMP/state"
FARHAND_LAUNCH="$TMP/launch.sh"
export FARHAND_STATE FARHAND_LAUNCH

# stand-in launcher: alive() checks the cmdline for launch.sh
printf '#!/usr/bin/env bash\nsleep 30\n' > "$FARHAND_LAUNCH"

cleanup() {
  pkill -f "$TMP" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

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

w() { bash "$WATCHER_SH" "$@"; }

# reconcile only runs inside the poll loop, so start the loop, let it get
# through one pass, and keep the first line it prints
reconcile_line() {
  FARHAND_POLL=1 timeout 2 bash "$WATCHER_SH" run 2>&1 | head -n 1
}

echo "watcher.sh"

is "empty state is idle"  "$(w status)"  "idle"

out="$(w start qe j1)"
pid="$(cat "$FARHAND_STATE/job.pid")"
is "start reports the pid"  "$out"  "started j1 (pid $pid)"
is "status sees the job"  "$(w status)"  "running j1 (pid $pid)"

w start qe j2 2>/dev/null
is "second start is refused"  "$?"  "1"
is "refusal keeps the first job"  "$(cat "$FARHAND_STATE/job.name")"  "j1"

is "restart adopts a live job"  "$(reconcile_line)"  "reconcile: adopted j1 (pid $pid)"

# a reboot invalidates every recorded pid, even if the number is in use again
real_boot="$(cat "$FARHAND_STATE/job.boot")"
echo "not-this-boot" > "$FARHAND_STATE/job.boot"
is "other boot id is not adopted"  "$(w status)"  "stale: j1 (pid $pid) is gone"
echo "$real_boot" > "$FARHAND_STATE/job.boot"

pkill -f "$TMP" 2>/dev/null
sleep 0.2
is "dead job shows as stale"  "$(w status)"  "stale: j1 (pid $pid) is gone"
is "restart cleans a stale job"  "$(reconcile_line)"  "reconcile: cleaning stale j1 (pid $pid)"
is "cleaned state is idle"  "$(w status)"  "idle"

# a recycled pid: alive, right boot, but not our launcher
sleep 30 &
echo "$!" > "$FARHAND_STATE/job.pid"
echo j3 > "$FARHAND_STATE/job.name"
cat /proc/sys/kernel/random/boot_id > "$FARHAND_STATE/job.boot"
is "foreign process is not adopted"  "$(w status)"  "stale: j3 (pid $!) is gone"
kill "$!" 2>/dev/null
rm -f "$FARHAND_STATE"/job.*

# trigger protocol: a file dropped in triggers/ is consumed and started
mkdir -p "$FARHAND_STATE/triggers"
touch "$FARHAND_STATE/triggers/run.qe.j4.$(date +%s.%N)"
FARHAND_POLL=1 timeout 2 bash "$WATCHER_SH" run >/dev/null 2>&1
is "trigger starts the job"  "$(cat "$FARHAND_STATE/job.name" 2>/dev/null)"  "j4"
is "trigger file is consumed"  "$(ls -A "$FARHAND_STATE/triggers")"  ""

# job names may contain dots. only the trailing timestamp is stripped
rm -f "$FARHAND_STATE"/job.*
pkill -f "$TMP/launch.sh" 2>/dev/null
touch "$FARHAND_STATE/triggers/run.qe.h2o.v2.$(date +%s.%N)"
FARHAND_POLL=1 timeout 2 bash "$WATCHER_SH" run >/dev/null 2>&1
is "dotted job name survives" "$(cat "$FARHAND_STATE/job.name" 2>/dev/null)" "h2o.v2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

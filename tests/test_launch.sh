#!/usr/bin/env bash
# Behavioural tests for launch.sh. Run: bash tests/test_launch.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LAUNCH="$HERE/../launch/launch.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export FARHAND_ENGINES_CONF="$TMP/engines.conf"
export FARHAND_WORK="$TMP/work"

cat > "$FARHAND_ENGINES_CONF" << 'EOF'
# a comment, and a blank line follow

[demo]
pin = 0-1
run = echo starting __JOB__; echo JOB DONE
ok  = grep -q 'JOB DONE' run.log

[silent]
pin = 0-1
run = echo nothing useful
ok  = grep -q 'JOB DONE' run.log

[trusting]
pin = 0-1
run = exit 3
ok  = exit0

[withequals]
pin = 0-1
run = FOO=bar; echo "value=$FOO"
ok  = exit0
EOF

mkdir -p "$FARHAND_WORK"/{good,silent,trusting,eq,clean}

pass=0
fail=0
is()     { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1";
           else fail=$((fail+1)); printf '  FAIL %s (expected: %s, got: %s)\n' "$1" "$3" "$2"; fi; }

l() { bash "$LAUNCH" "$@" 2>/dev/null; }

has() {
	if grep -q "$3" "$2" 2>/dev/null; then
		pass=$((pass + 1)); printf '  ok %s\n' "$1"
	else
		fail=$((fail + 1)); printf '  FAIL %s (%s does not contain: %s)\n' "$1" "$2" "$3"
	fi
}

absent() {
	if [ ! -e "$2" ]; then
		pass=$((pass + 1)); printf '  ok  %s\n' "$1"
	else
		fail=$((fail + 1)); printf '  FAIL %s (%s exists)\n' "$1" "$2"
	fi
}

echo "launch.sh"

# --- success path
l demo good
is "success exits 0"        "$?"                              "0"
is "status is done"         "$(cat "$FARHAND_WORK/good/status")" "done"
is "rc file records 0"      "$(cat "$FARHAND_WORK/good/rc")"     "0"
has "log captured output"   "$FARHAND_WORK/good/run.log"      "JOB DONE"
has "__JOB__ substituted"   "$FARHAND_WORK/good/run.log"      "starting good"

# --- the bug: command succeeds, job did not
l silent silent
is "failed check exits 1"   "$?"                                   "1"
is "status is failed"       "$(cat "$FARHAND_WORK/silent/status")" "failed"
is "rc still records 0"     "$(cat "$FARHAND_WORK/silent/rc")"     "0"

# --- exit0 mode
l trusting trusting
is "exit0 mode fails on rc" "$?"                                     "1"
is "rc file records 3"      "$(cat "$FARHAND_WORK/trusting/rc")"     "3"

# --- parser edge: value containing '='
l withequals eq
is "value with = survives"  "$?"                              "0"
has "command ran intact"    "$FARHAND_WORK/eq/run.log"        "value=bar"

# --- refusals must not touch the filesystem
l nosuchengine clean
is "unknown engine exits 2" "$?" "2"
absent "no status written"  "$FARHAND_WORK/clean/status"
absent "no log written"     "$FARHAND_WORK/clean/run.log"

l demo nosuchjob
is "missing job dir exits 2" "$?" "2"

# --- no temp files left behind by set_state
absent "no status.tmp left"  "$FARHAND_WORK/good/status.tmp"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

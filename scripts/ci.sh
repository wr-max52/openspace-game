#!/usr/bin/env bash
# The merge gate (issue #545). Two questions, and nothing else:
#   1. Does the game start? The main scene on a first launch (New Game menu, Enter,
#      Story) and on the next launch (the save goes on), with no script error.
#   2. Do the key moments stay smooth? Walking the town, walking out into the
#      desert, the ship from the pit to space and back, and flying between planets,
#      each with its frame budget.
# Plus the IP rule (file scan and commit messages), which is cheap and absolute.
#
# Every step, trace or test, also fails on a script error in its own log.
# The whole gate gets 30 minutes (CI_BUDGET_S); a step still running when it is
# spent is killed with everything it started, and the gate fails naming it.
#
# The rest of the suite (every system's own checks) is scripts/test_all.sh: run it
# for the system you change. It does not block a merge.
#
# Run: ./scripts/ci.sh            (GODOT_BIN=/path/to/godot to pick the engine)
set -euo pipefail

cd "$(dirname "$0")/.."

# Issue #548: commit messages are under the IP rule too (the GUT scan covers files).
./scripts/check_commit_messages.sh

GODOT_BIN="${GODOT_BIN:-godot}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/godot ]; then GODOT_BIN=/opt/homebrew/bin/godot; fi
  if [ -x /usr/local/bin/godot ]; then GODOT_BIN=/usr/local/bin/godot; fi
fi

# Pin check: the engine must be the version we locked. 4.7.2 pins 4.7.2.stable.*,
# never 4.7.20 or 4.7.
PIN="$(cat scripts/pin.txt)"
GODOT_VER="$("$GODOT_BIN" --version 2>/dev/null || true)"
echo "CI: pinned=$PIN  actual=$GODOT_VER"
case "$GODOT_VER" in
  "$PIN" | "$PIN".*) ;;
  *)
    echo "CI: ERROR -- Godot $GODOT_VER is not the pinned $PIN (scripts/pin.txt)" >&2
    exit 1
    ;;
esac

CI_BUDGET_S="${CI_BUDGET_S:-1800}"
CI_START=$SECONDS
# Steps send their own output (stderr too) to a log or /dev/null; the budget's
# error goes to the gate's stderr, kept here as fd 3, so it is never swallowed.
exec 3>&2

# Run a step under the time left. It runs in its own process group so the alarm
# takes its children too. Returns the step's exit code; exits the gate when the
# budget runs out.
within_budget() {
  local left=$(( CI_BUDGET_S - (SECONDS - CI_START) ))
  if [ "$left" -le 0 ]; then
    echo "CI: ERROR -- over the $((CI_BUDGET_S / 60))-minute budget before: $*" >&3
    exit 1
  fi
  local rc=0
  perl -e '
    my $t = shift; my $pid = fork // die "fork: $!";
    if (!$pid) { setpgrp(0, 0); exec @ARGV or die "exec $ARGV[0]: $!"; }
    my $stop = sub { kill "KILL", -$pid; waitpid($pid, 0); exit $_[0]; };
    $SIG{ALRM} = sub { $stop->(142) };
    $SIG{INT} = $SIG{TERM} = sub { $stop->(130) };
    alarm $t; waitpid($pid, 0);
    exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
  ' "$left" "$@" || rc=$?
  if [ "$rc" -eq 142 ]; then
    echo "CI: ERROR -- over the $((CI_BUDGET_S / 60))-minute budget ($((SECONDS - CI_START)) s) in: $*" >&3
    exit 1
  fi
  return "$rc"
}

# A trace left over from an earlier run must not satisfy a check.
rm -rf test_results
mkdir -p test_results/logs

# A script error is a break even when Godot exits 0 (a release build crashes
# where a debug build only logs).
no_script_errors() {
  local log="$1"
  if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|Invalid call|Invalid access' "$log"; then
    echo "CI: ERROR -- script error in $log:" >&2
    grep -E -m 10 -A 3 'SCRIPT ERROR|Parse Error|Failed to load script|Invalid call|Invalid access' "$log" >&2
    exit 1
  fi
}

# Run one Godot step: name, the file it must write ("" for none), then Godot's
# arguments. Its output goes to test_results/logs/<name>.log.
step() {
  local name="$1" out="$2"; shift 2
  local log="test_results/logs/$name.log" t0=$SECONDS rc=0
  echo "CI: $name..."
  within_budget "$@" >"$log" 2>&1 || rc=$?
  no_script_errors "$log"
  if [ "$rc" -ne 0 ]; then
    echo "CI: ERROR -- $name exited $rc (log: $log)" >&2
    tail -n 30 "$log" >&2
    exit 1
  fi
  if [ -n "$out" ] && [ ! -f "$out" ]; then
    echo "CI: ERROR -- $name did not write $out (log: $log)" >&2
    tail -n 30 "$log" >&2
    exit 1
  fi
  echo "CI: $name ok ($((SECONDS - t0)) s)"
}

G=("$GODOT_BIN" --headless --path .)

# Register class_names and import assets. On a fresh checkout without .godot/,
# nothing else can start until this has run.
echo "CI: importing project..."
within_budget "${G[@]}" --import >test_results/logs/import.log 2>&1 || true

# 1. The game starts. An empty home folder so user:// holds no save, no settings:
#    a first launch on a new machine. Both launches share it, as two launches do.
BOOT_HOME="$(mktemp -d "${TMPDIR:-/tmp}/openspace-boot.XXXXXX")"
trap 'rm -rf "$BOOT_HOME"' EXIT
BOOT=(env BOOT_HOME="$BOOT_HOME" HOME="$BOOT_HOME" XDG_DATA_HOME="$BOOT_HOME/.local/share"
  XDG_CONFIG_HOME="$BOOT_HOME/.config")
step boot_first test_results/boot_first.txt "${BOOT[@]}" "${G[@]}" -s res://scenes/boot_trace.gd -- phase=first
step boot_again test_results/boot_again.txt "${BOOT[@]}" "${G[@]}" -s res://scenes/boot_trace.gd -- phase=again
# For the record, not a budget (headless the look is all CPU, with no GPU or culling).
for p in first again; do
  echo "CI: boot_$p frames in the port, look on: median $(grep '^median_ms=' test_results/boot_$p.txt | cut -d= -f2) ms," \
    "worst $(grep '^worst_ms=' test_results/boot_$p.txt | cut -d= -f2) ms"
done

# 2. The key moments, with real physics on the real town.
#    Spawn, ramp, cantina, gate, back gap: the town walk (50 ms budget).
step town_walk test_results/town_walk_trace.txt "${G[@]}" --fixed-fps 60 -s res://scenes/town_walk_trace.gd
#    Out of the gate onto the sand and 700 m into the dunes and back (50 ms).
step desert_walk test_results/desert_walk_trace.txt "${G[@]}" --fixed-fps 60 -s res://scenes/desert_walk_trace.gd
#    Board in the pit, lift off, climb to space, dive back, fly round, land (50 ms).
step m14_flight test_results/m14_flight_trace.txt "${G[@]}" --fixed-fps 60 -s res://scenes/m14_flight_trace.gd
#    Port to space to another planet and home, no fade, staged handoffs (50 ms).
step planets test_results/planets_trace.txt "${G[@]}" --fixed-fps 60 -s res://scenes/planets_trace.gd

# The checks on those traces, the handoff seams, and the IP scan. Nothing else:
# tests/ holds every system's own tests, and scripts/test_all.sh runs them.
# (test_staged_build is not here: the planets trace checks staged handoffs on the
# real flight, and that suite leaks whole towns, which aborts Godot's exit.)
GATE_TESTS=(
  test_boot
  test_town_walk
  test_desert_walk
  test_m14_flight
  test_planets_trace
  test_handoff_seams
  test_ip_neutral
)
GTEST=""
for t in "${GATE_TESTS[@]}"; do GTEST+="${GTEST:+,}res://tests/$t.gut.gd"; done
step tests test_results/junit.xml "${G[@]}" -s res://addons/gut/gut_cmdln.gd \
  -gtest="$GTEST" -gexit=true -gjunit_xml_file=res://test_results/junit.xml
grep -E 'Passing|Failing|Pending|Asserts|Time' test_results/logs/tests.log | tail -n 6 || true

echo "CI: green ($((SECONDS - CI_START)) s of the $((CI_BUDGET_S / 60))-minute budget)"

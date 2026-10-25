#!/usr/bin/env bash
# Tests for ygg-clean.sh.   scripts/tests/ygg-clean.test.sh
# Made-up projects with run folders and a fake `ygg` that logs its calls. A live run is a real flock on its lock
# file (flock(1)), as ygg takes it, read back from /proc/locks. The whole test runs under env -i (hermetic.sh): no
# engine, no real ygg, nothing outside its folder is touched.
# shellcheck disable=SC2329 # check calls has and hasnt by name
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$HERE/hermetic.sh"
HERMETIC_TOOLS="python3" hermetic_enter "$@"
S="$HERE/.."
holders=()
trap 'for p in "${holders[@]}"; do kill "$p" 2>/dev/null; done; rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
# run CMD...: a case. Its PATH must stay in T (and /usr/bin:/bin), or the test stops before anything runs.
run() {
  hermetic_path_ok "$PATH" || { echo "FAIL the test's PATH leaves its folder: $PATH"; exit 3; }
  "$@" >"$T/out" 2>&1; rc=$?
}
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
export YGG_ENGINE_CHECK=0 # the engine environment has its own test (ygg-engine.test.sh)

# The folder: factory.yaml, and projects. Each smoke folder has factory.yaml beside its project.
D="$T/it"; mkdir -p "$D"
printf 'engine: unix://%s/engine.sock\n' "$T" >"$D/factory.yaml"
mkproject() { # NAME RUNS...: DIR/NAME/project with those run folders, and a factory.yaml beside it
  local n="$1"; shift
  mkdir -p "$D/$n/project/.factory/runs"
  printf 'sandbox: {}\n' >"$D/$n/factory.yaml"
  for r in "$@"; do mkdir -p "$D/$n/project/.factory/runs/$r"; : >"$D/$n/project/.factory/runs/$r/lock"; printf '{}\n' >"$D/$n/project/.factory/runs/$r/run.json"; done
}
mkproject smoke-a 20261024-000001-aaaaaa
mkproject smoke-b 20261024-000002-bbbbbb
mkproject proof-keep 20261024-000003-cccccc
mkproject smoke-live 20261024-000004-dddddd 20261024-000005-eeeeee
mkproject smoke-busy 20261024-000008-222222
mkproject smoke-noconf 20261024-000006-ffffff; rm "$D/smoke-noconf/factory.yaml"
mkproject smoke-rec 20261024-000007-111111; rm "$D/smoke-rec/factory.yaml"
printf 'sandbox: {}\n' >"$T/recorded.yaml"
printf '{"id": "x", "config_path": "%s", "graph": "software"}\n' "$T/recorded.yaml" >"$D/smoke-rec/project/.factory/runs/20261024-000007-111111/run.json"
# A folder the script must not look into, and folders that are not projects.
mkdir -p "$D/hidden-suites/x/.factory/runs" "$D/dc/node_modules/.factory/runs" "$D/empty"

# A lock is held when /proc/locks has a FLOCK line for its device and inode, as odin's lock.Held reads it. The cases
# read a made-up /proc/locks (YGG_LOCKS_FILE): in a sandbox with its own PID namespace the kernel leaves this test's
# own locks out of /proc/locks. The last case takes a real lock and reads the real file, when the kernel shows it.
export YGG_LOCKS_FILE="$T/locks"; : >"$YGG_LOCKS_FILE"
hold() { # LOCKFILE: write the line the kernel would, from Python's own view of the device
  mkdir -p "$(dirname "$1")"; : >>"$1"
  python3 -I - "$1" >>"$YGG_LOCKS_FILE" <<'PY'
import os, sys
st = os.stat(sys.argv[1])
print(f"1: FLOCK  ADVISORY  WRITE 4242 {os.major(st.st_dev):02x}:{os.minor(st.st_dev):02x}:{st.st_ino} 0 EOF")
PY
}
printf '2: POSIX  ADVISORY  WRITE 4243 00:00:1 0 EOF\n' >>"$YGG_LOCKS_FILE"
hold "$D/smoke-live/project/.factory/runs/20261024-000005-eeeeee/lock"
hold "$D/smoke-busy/project/.factory/locks/runs.lock" # a ygg that advances some run of that project
# The second check does not need /proc/locks: a process with the lock file open, seen through PROC/PID/fd links.
# The cases read a made-up proc folder (YGG_PROC_DIR); a last case reads the real /proc.
export YGG_PROC_DIR="$T/proc"; mkdir -p "$YGG_PROC_DIR/1/fd"; ln -s /dev/null "$YGG_PROC_DIR/1/fd/0"
mkproject smoke-open 20261024-000010-444444
mkdir -p "$YGG_PROC_DIR/4244/fd"
ln -s "$D/smoke-open/project/.factory/runs/20261024-000010-444444/lock" "$YGG_PROC_DIR/4244/fd/7"

# The fake ygg: logs its arguments; doctor of smoke-b reports a removed pod and a removed grader; FAKE_DOCTOR_RC
# sets its exit.
FB="$T/fakebin"; mkdir -p "$FB"
cat >"$FB/ygg" <<'EOF2'
#!/usr/bin/env bash
echo "ygg $*" >>"$FAKE_LOG"
if [ "$1" = doctor ]; then
  echo "OK    config: fake"
  case "$*" in *smoke-b*)
    echo "WARN  pods: run 20261024-000002-bbbbbb left the empty pod pod_abc123 (Created); removed it"
    echo "WARN  graders: run 20261024-000002-bbbbbb left the grader container 0123456789ab (exited); removed it"
    echo "OK    pods: 1 empty pod(s) of ygg runs" ;;
  esac
  exit "${FAKE_DOCTOR_RC:-0}"
fi
exit 0
EOF2
chmod +x "$FB/ygg"
export FAKE_LOG="$T/calls.log"
PATH="$FB:$BASEPATH"
: >"$FAKE_LOG"

check "the test's own PATH is only its folders and /usr/bin:/bin" hermetic_path_ok "$PATH"

# --- --dry-run: lists and changes nothing, and never reaches the engine (even with the engine check on)
snap() { find "$D" -printf '%p %s %T@\n' | sort | sha256sum; }
before="$(snap)"
YGG_ENGINE_CHECK=1 run "$S/ygg-clean.sh" --dry-run --folder "$D" --keep "$D/proof-keep"
check "a dry run exits 0" test "$rc" -eq 0
check "a dry run runs no ygg" bash -c "[ ! -s '$FAKE_LOG' ]"
check "a dry run changes no file or folder" test "$before" = "$(snap)"
check "it lists the doctor it would run" has "would run: ygg doctor --project $D/smoke-a/project --config $D/smoke-a/factory.yaml"
check "it says the summary is of a dry run" has "summary (dry run: nothing was changed)"
check "it never names hidden-suites" hasnt "hidden-suites"
check "it never takes a folder that is no project" bash -c "! grep -q -F '$D/empty' '$T/out' && ! grep -q -F '$D/dc/' '$T/out'"

# --- the real clean
: >"$FAKE_LOG"
run "$S/ygg-clean.sh" --folder "$D" --keep "$D/proof-keep"
check "a clean exits 0" test "$rc" -eq 0
check "doctor ran for a quiet project" grep -q -F "ygg doctor --project $D/smoke-a/project --config $D/smoke-a/factory.yaml" "$FAKE_LOG"
check "doctor ran for the project with pods" grep -q -F "ygg doctor --project $D/smoke-b/project --config $D/smoke-b/factory.yaml" "$FAKE_LOG"
check "--keep by path: the kept project is not cleaned" bash -c "! grep -q proof-keep '$FAKE_LOG'"
check "--keep is said in the summary" has "kept: $D/proof-keep/project"
check "a project with a live run is not cleaned" bash -c "! grep -q smoke-live '$FAKE_LOG'"
check "the live run is said in the summary" has "skipped: $D/smoke-live/project: run 20261024-000005-eeeeee is live (a process holds its lock)"
check "a project whose runs lock is held is not cleaned" bash -c "! grep -q smoke-busy '$FAKE_LOG'"
check "and the summary says why" has "skipped: $D/smoke-busy/project: a ygg process holds the project's runs lock"
check "a run whose lock a process has open (not in /proc/locks) is not cleaned" bash -c "! grep -q smoke-open '$FAKE_LOG'"
check "and the summary names the process" has "skipped: $D/smoke-open/project: run 20261024-000010-444444 is live (process 4244 has its lock open)"
check "a project with no config is skipped, with a message" has "skipped: $D/smoke-noconf/project: no config found"
check "the run's recorded config is used" grep -q -F "ygg doctor --project $D/smoke-rec/project --config $T/recorded.yaml" "$FAKE_LOG"
check "hidden-suites is never cleaned or named" bash -c "! grep -q hidden-suites '$FAKE_LOG' && ! grep -q hidden-suites '$T/out'"
check "the summary lists the cleaned projects" has "cleaned: $D/smoke-b/project"
check "the summary lists the pods doctor removed" has "$D/smoke-b/project: run 20261024-000002-bbbbbb left the empty pod pod_abc123 (Created); removed it"
check "and the leftover containers it removed" has "left the grader container 0123456789ab (exited); removed it"
check "no ygg verb but doctor was called" bash -c "! grep -v '^ygg doctor ' '$FAKE_LOG' | grep -q ."
check "no run folder was deleted" bash -c "[ -d '$D/smoke-a/project/.factory/runs/20261024-000001-aaaaaa' ] && [ -d '$D/smoke-b/project/.factory/runs/20261024-000002-bbbbbb' ]"

# --- --keep by name (the folder name under DIR), more than once
: >"$FAKE_LOG"
run "$S/ygg-clean.sh" --folder "$D" --keep proof-keep --keep smoke-a
check "--keep by name works" bash -c "! grep -q 'proof-keep' '$FAKE_LOG' && ! grep -q 'smoke-a' '$FAKE_LOG'"
check "and the others are still cleaned" grep -q -F "smoke-b/project" "$FAKE_LOG"
run "$S/ygg-clean.sh" --folder "$D" --keep nothing-here
check "a --keep that names no folder is a refusal" bash -c "[ $rc -eq 2 ] && grep -q 'nothing-here' '$T/out'"

# --- a bare name is a folder under DIR first, then one in the caller's folder
mkdir -p "$T/cwd/smoke-a"
: >"$FAKE_LOG"
(cd "$T/cwd" && run "$S/ygg-clean.sh" --folder "$D" --keep smoke-a; echo "$rc" >"$T/rc")
check "--keep smoke-a keeps DIR/smoke-a even when the caller's folder has a smoke-a" bash -c "[ \$(cat '$T/rc') -eq 0 ] && ! grep -q 'smoke-a' '$FAKE_LOG'"

# --- the locks file must be readable: without it the script cannot tell a live run, so it refuses
: >"$FAKE_LOG"
YGG_LOCKS_FILE="$T/no-locks" run "$S/ygg-clean.sh" --folder "$D" --dry-run
check "a locks file that is missing is a refusal (exit 2)" bash -c "[ $rc -eq 2 ] && grep -q -F 'cannot tell whether a run is live' '$T/out'"
check "and nothing ran" test ! -s "$FAKE_LOG"
cp "$YGG_LOCKS_FILE" "$T/locks-closed"; chmod 000 "$T/locks-closed"
YGG_LOCKS_FILE="$T/locks-closed" run "$S/ygg-clean.sh" --folder "$D" "$D/smoke-a/project"
check "a locks file that cannot be read is a refusal (exit 2)" bash -c "[ $rc -eq 2 ] && grep -q -F 'cannot tell whether a run is live' '$T/out' && [ ! -s '$FAKE_LOG' ]"
YGG_PROC_DIR="$T/no-proc" run "$S/ygg-clean.sh" --folder "$D" "$D/smoke-a/project"
check "a proc folder that cannot be read is a refusal (exit 2)" bash -c "[ $rc -eq 2 ] && grep -q -F 'cannot tell whether a run is live' '$T/out' && [ ! -s '$FAKE_LOG' ]"

# --- a project under DIR/hidden-suites is refused by its path, before it is entered
run "$S/ygg-clean.sh" --folder "$D" "$D/hidden-suites/x"
check "a named project under hidden-suites is refused (exit 2)" bash -c "[ $rc -eq 2 ] && grep -q -F 'is under $D/hidden-suites' '$T/out'"
run "$S/ygg-clean.sh" --folder "$D" hidden-suites/x
check "and so is its name under DIR" bash -c "[ $rc -eq 2 ] && grep -q -F 'is under $D/hidden-suites' '$T/out'"
run "$S/ygg-clean.sh" --folder "$D" "$D/smoke-a/../hidden-suites/x"
check "and a path that reaches it through .." bash -c "[ $rc -eq 2 ] && grep -q -F 'is under $D/hidden-suites' '$T/out'"
ln -s "$D/hidden-suites/x" "$T/sly"
run "$S/ygg-clean.sh" --folder "$D" "$T/sly"
check "and a link to it" bash -c "[ $rc -eq 2 ] && grep -q -F 'is under $D/hidden-suites' '$T/out'"

# --- named projects
: >"$FAKE_LOG"
run "$S/ygg-clean.sh" --folder "$D" "$D/smoke-a/project"
check "a named project is the only one cleaned" bash -c "[ \$(wc -l <'$FAKE_LOG') -eq 1 ] && grep -q smoke-a '$FAKE_LOG'"
: >"$FAKE_LOG"
run "$S/ygg-clean.sh" --folder "$D" "$D/smoke-live/project"
check "a named project with a live run is still skipped" bash -c "[ ! -s '$FAKE_LOG' ] && grep -q 'is live' '$T/out'"
run "$S/ygg-clean.sh" --folder "$D" "$D/nothing/project"
check "a named folder that is no project is a refusal" test "$rc" -eq 2

# --- a doctor that fails
: >"$FAKE_LOG"
FAKE_DOCTOR_RC=1 run "$S/ygg-clean.sh" --folder "$D" "$D/smoke-a/project"
check "a failing doctor makes the exit 1" test "$rc" -eq 1
check "and is in the summary" has "failed: $D/smoke-a/project (ygg doctor exit 1)"

# --- YGG_CMD names how ygg runs; no ygg at all is a refusal
: >"$FAKE_LOG"
PATH="$BASEPATH" YGG_CMD="$FB/ygg" run "$S/ygg-clean.sh" --folder "$D" "$D/smoke-a/project"
check "YGG_CMD is the ygg that runs" bash -c "[ $rc -eq 0 ] && grep -q smoke-a '$FAKE_LOG'"
PATH="$BASEPATH" run "$S/ygg-clean.sh" --folder "$D"
check "no ygg on PATH is a refusal" bash -c "[ $rc -eq 2 ] && grep -q 'no ygg on the path' '$T/out'"

# --- the engine environment of a real clean comes from ygg-engine.sh; when it refuses, no doctor runs
: >"$FAKE_LOG"
YGG_ENGINE_CHECK=1 run "$S/ygg-clean.sh" --folder "$D" "$D/smoke-a/project"
check "a refusal of ygg-engine.sh (no socket) stops the clean (exit 2)" bash -c "[ $rc -eq 2 ] && grep -q 'ygg-engine:' '$T/out'"
check "and no doctor ran" test ! -s "$FAKE_LOG"

# --- bad flags
run "$S/ygg-clean.sh" --folder
check "a flag with no value is a usage error" test "$rc" -eq 2
run "$S/ygg-clean.sh" --nope
check "an unknown flag is a usage error" test "$rc" -eq 2

# --- a real lock, read from the real /proc/locks, when this kernel shows this test's locks there
mkproject real-live 20261024-000009-333333
real="$D/real-live/project/.factory/runs/20261024-000009-333333/lock"
# The subshell becomes the sleep, which keeps fd 9 and its lock: killing it frees the lock.
( exec 9>>"$real"; flock -x 9; exec sleep 300 ) & holders+=("$!")
for _ in $(seq 50); do flock -n "$real" true || break; sleep 0.1; done
if grep -q -E " FLOCK .*:$(stat -c %i "$real") " /proc/locks; then
  : >"$FAKE_LOG"
  YGG_LOCKS_FILE=/proc/locks run "$S/ygg-clean.sh" --folder "$D" "$D/real-live/project"
  check "a run whose lock a live process holds (the real /proc/locks) is skipped" bash -c "[ ! -s '$FAKE_LOG' ] && grep -q 'is live' '$T/out'"
  check "and the process that holds it still runs" kill -0 "${holders[0]}"
else
  echo "skip a real lock: this kernel leaves the test's own locks out of /proc/locks (another PID namespace)"
fi
for p in "${holders[@]}"; do kill "$p" 2>/dev/null; done

# --- a real process with a run's lock open, read from the real /proc, with nothing in the locks file
mkproject real-open 20261024-000011-555555
real2="$D/real-open/project/.factory/runs/20261024-000011-555555/lock"
( exec 9>>"$real2"; flock -x 9; exec sleep 300 ) & holders+=("$!")
for _ in $(seq 50); do flock -n "$real2" true || break; sleep 0.1; done
: >"$FAKE_LOG"; : >"$T/locks-empty"
YGG_PROC_DIR=/proc YGG_LOCKS_FILE="$T/locks-empty" run "$S/ygg-clean.sh" --folder "$D" "$D/real-open/project"
check "a run whose lock a real process has open is skipped (the real /proc fd links)" bash -c "[ ! -s '$FAKE_LOG' ] && grep -q -F 'run 20261024-000011-555555 is live (process ' '$T/out'"
check "and that process still runs" kill -0 "${holders[-1]}"
for p in "${holders[@]}"; do kill "$p" 2>/dev/null; done

hermetic_done
echo; [ "$fail" -eq 0 ] && echo "ygg-clean.test.sh: all ok" || echo "ygg-clean.test.sh: FAILURES"
exit "$fail"

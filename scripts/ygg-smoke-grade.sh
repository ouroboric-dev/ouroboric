#!/usr/bin/env bash
# Run the grader smoke (v0-H16): `ygg run` with scripted agents on a real engine, ending in the grade node, then
# `ygg grade` again, on the reference solution and on an empty product of the task smoke-notes.
#   ygg-smoke-grade.sh [--build] [--folder DIR] [--tasks DIR] [--odin DIR] [--limits] [--clip]
# The suite is the PUBLIC sample suite of the task (smoke-notes/sample-suite/tests): this script never reads or
# writes a hidden suite. It copies the public suite into DIR/smoke-grade-<time>/suites/smoke-notes/v1/tests, and
# that folder is the grader's suite_dir. Needs DIR/factory.yaml (it names the engine; this script never writes
# it), the devcontainer CLI 0.89.0, jq and python3, the engine up, the bind mount present, and a checkout of
# `mimir` (--tasks, default: the mimir folder next to this repo in the umbrella). It
#   1. checks the engine (ygg-engine.sh), the tools and the task;
#   2. makes DIR/smoke-grade-<time> with one project per case (reference, empty), each with a committed
#      `start.sh` that starts the leaf's own, because the grader's /app is the project, and the leaf is in repos/notes;
#   3. writes the scripted answers from the reference solution of the task (the files are not copied by hand);
#   4. runs `ygg run` on each project (the brief is the task's instruction.md; the graph ends in the grade node),
#      and watches the engine while it runs;
#      (--build first builds the sandbox image of the realm, which a first run needs);
#   5. runs `ygg grade` on each finished run, and prints one line per check: PASS or FAIL.
# The checks: reward 1 for the reference; reward below 1 for the empty product; no container with the label
# ygg.grader is left; ygg doctor finds none; no container that is not a grader ever held the suite folder
# (the engine is polled every second while the run goes); score.json is in the run folder and in no other place.
# Exit 0 only when every check passes. The grader runs without a memory or CPU limit (grader.memory: none,
# cpus: 0), because rootless Podman without cgroup delegation cannot apply them; --limits asks for 4g and 4 CPUs.
# Defaults: DIR=$HOME/ygg-it. For tests and other machines: YGG_CMD (how ygg runs), YGG_ODIN (the odin folder),
# YGG_BIND (the bind mount, default /mnt/wsl/ygg-bind), YGG_CLI_VERSION (default 0.89.0). The engine environment
# comes from ygg-engine.sh (YGG_ENGINE_CHECK=0 skips it).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="$HOME/ygg-it" tasks="$HERE/../../mimir" limits=0 clip=0 build=0
odin="${YGG_ODIN:-$HERE/../../yggdrasil/odin}"
usage() { echo "usage: ygg-smoke-grade.sh [--folder DIR] [--tasks DIR] [--odin DIR] [--build] [--limits] [--clip]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --folder) [ $# -ge 2 ] || usage; dir="$2"; shift 2 ;;
    --tasks) [ $# -ge 2 ] || usage; tasks="$2"; shift 2 ;;
    --odin) [ $# -ge 2 ] || usage; odin="$2"; shift 2 ;;
    --build) build=1; shift ;;
    --limits) limits=1; shift ;;
    --clip) clip=1; shift ;;
    *) usage ;;
  esac
done
fail() { echo "smoke-grade: $*" >&2; exit 2; }
task=smoke-notes
bind="${YGG_BIND:-/mnt/wsl/ygg-bind}"

export PATH="$dir/dc/node_modules/.bin:$PATH"
if [ "${YGG_ENGINE_CHECK:-1}" = 1 ]; then
  engine_env="$("$HERE/ygg-engine.sh" env --folder "$dir")" || exit 2
  eval "$engine_env"
fi
[ -f "$dir/factory.yaml" ] || fail "$dir/factory.yaml is missing; it names the engine (sandbox.engine)"
engine="$(sed -n 's/^[[:space:]]*engine:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$dir/factory.yaml" | head -n 1)"
case "$engine" in unix://*) ;; *) fail "sandbox.engine in $dir/factory.yaml is '${engine:-missing}'; it must be a unix:// URL" ;; esac
for tool in jq python3 podman git; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"; done
tasks="$(cd "$tasks" 2>/dev/null && pwd)" || fail "no mimir folder at $tasks (--tasks)"
odin="$(cd "$odin" 2>/dev/null && pwd)" || fail "no odin folder at $odin (--odin)"
realm="$odin/testdata/smoke-grade"
public="$tasks/$task/sample-suite"
for f in "$tasks/$task/task.toml" "$tasks/$task/instruction.md" "$public/tests/manifest.json" "$public/tests/test.sh" "$public/reference/start.sh" "$realm/pack.yaml"; do
  [ -f "$f" ] || fail "$f is missing"
done
suite="$(sed -n 's/^suite[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$tasks/$task/task.toml" | head -n 1)"
[ -n "$suite" ] || fail "$tasks/$task/task.toml has no metadata.suite"

work="$dir/smoke-grade-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$work/suites/$task/$suite"
cp -r "$public/tests" "$work/suites/$task/$suite/tests"
echo "smoke-grade: made $work"
echo "smoke-grade: the suite is the PUBLIC sample suite $public/tests (suite $suite)"

ygg="${YGG_CMD:-}"
if [ -z "$ygg" ]; then
  if command -v ygg >/dev/null 2>&1; then ygg=ygg
  else
    mkdir -p "$work/bin"
    (cd "$odin" && go build -o "$work/bin/ygg" ./cmd/ygg) || fail "go build of ygg failed in $odin"
    ygg="'$work/bin/ygg'"
  fi
fi

# The scripted answers: the implementer writes the files of the case; the reviewer finds nothing.
script() { # script CASE OUT: reference writes every file of the task's reference solution; empty writes a README
  python3 -I - "$1" "$public/reference" >"$2" <<'PY'
import json, os, sys
case, ref = sys.argv[1], sys.argv[2]
usage = "usage: { in: 2000, out: 400, turns: 5 }"
print("steps:\n  build:\n    - actions:")
if case == "reference":
    for name in sorted(os.listdir(ref)):
        with open(os.path.join(ref, name), encoding="utf-8") as f:
            print("        - write: { path: %s, content: %s }" % (json.dumps(name), json.dumps(f.read())))
    print('        - run: { argv: ["chmod", "+x", "start.sh"] }')
else:
    print("        - write: { path: README.md, content: %s }" % json.dumps("Nothing is built here.\n"))
print("      result: { status: ok, summary: built it, %s }" % usage)
print("  build-review:\n    - result: { status: ok, summary: reviewed, report: [], usage: { in: 800, out: 100, turns: 2 } }")
PY
}

# config CASE: the factory.yaml of a case, on stdout.
config() {
  local memory=none cpus=0
  [ "$limits" -eq 0 ] || { memory=4g cpus=4; }
  cat <<EOF
mode: unattended
privacy: strict
roles:
  implementer: { agent: scripted, model: none, script: $work/$1/script.yaml }
  reviewer: { agent: scripted, model: none, script: $work/$1/script.yaml }
budget:
  per_run: { tokens: 100000, turns: 100 }
  per_day: { tokens: 1000000, turns: 1000 }
sandbox:
  engine: $engine
  mounts:
    - { host: $dir, engine: $bind }
grader:
  tasks_dir: $tasks
  suite_dir: $work/suites
  timeout: 10m
  memory: $memory
  cpus: $cpus
EOF
}

results=() bad=0
check() { # check DESCRIPTION COMMAND...: PASS when the command succeeds
  local d="$1"
  shift
  if "$@" >/dev/null 2>&1; then echo "PASS  $d"; results+=("PASS  $d"); else echo "FAIL  $d"; results+=("FAIL  $d"); bad=1; fi
}
# Conditions for check, one per kind.
is_done() { [ "$1" -eq 0 ] && [ -n "$2" ]; }
is_zero() { [ "$1" -eq 0 ]; }
is_empty() { [ -z "$1" ]; }
is_same() { [ "$1" = "$2" ]; }
is_count() { [ "$(grep -Ec "$2" "$1")" -eq "$3" ]; }
seen_agents() { # seen_agents LOG MINE: how many containers of this run (they mount a path under MINE) the watch saw, grader excluded
  awk -v m="$2" '$2 == "-" && index($0, m) {print $1}' "$1" | sort -u | wc -l
}
not_held() { # not_held LOG NEEDLE MINE: the watch saw containers of this run, and none that is not a grader held NEEDLE
  [ "$(seen_agents "$1" "$3")" -gt 0 ] && ! awk -v n="$2" '$2 == "-" && index($0, n)' "$1" | grep -q .
}
held() { # held LOG NEEDLE: the grader container (it has the label) held NEEDLE
  awk -v n="$2" '$2 != "-" && index($0, n)' "$1" | grep -q .
}

# watch FILE: polls the engine until the file FILE.stop exists; writes one line per container and poll:
# "<name> <grader label or -> <mount sources...>".
watch() {
  while [ ! -e "$1.stop" ]; do
    ids="$(podman ps -a -q 2>/dev/null || true)"
    if [ -n "$ids" ]; then
      # shellcheck disable=SC2086
      podman inspect --format '{{.Name}} {{or (index .Config.Labels "ygg.grader") "-"}} {{range .Mounts}}{{.Source}} {{end}}' $ids >>"$1" 2>/dev/null || true
    fi
    sleep 1
  done
}

oneCase() { # oneCase CASE: build the project, run it to its end, grade it again
  local c="$1" v="$work/$1" project id rc
  project="$v/project"
  mkdir -p "$project"
  git -C "$project" init -q -b main
  printf 'root: true\nowner: ouroboric-dev\nvisibility: private\n' >"$project/umbrella.yaml"
  # The grader's /app is the project. The product is the leaf's; this file starts it.
  # shellcheck disable=SC2016
  printf '#!/bin/sh\ncd "$(dirname "$0")/repos/notes" && exec ./start.sh\n' >"$project/start.sh"
  chmod +x "$project/start.sh"
  git -C "$project" add umbrella.yaml start.sh
  git -C "$project" -c user.name=ygg -c user.email=ygg@example.invalid commit -q -m "the grader smoke project"
  script "$c" "$v/script.yaml"
  config "$c" >"$v/factory.yaml"
  : >"$v/mounts.log"
  watch "$v/mounts.log" &
  watcher=$! watchlog="$v/mounts.log"
  # An interrupt or an early exit must not leave the poller running.
  trap 'touch "$watchlog.stop"; kill "$watcher" 2>/dev/null || true' EXIT
  set +e
  eval "$ygg run --project '$project' --config '$v/factory.yaml' --realm '$realm' --brief '$tasks/$task/instruction.md'" 2>&1 | tee "$v/run.txt"
  rc="${PIPESTATUS[0]}"
  set -e
  id="$(find "$project/.factory/runs" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n 1 || true)"
  check "$c: ygg run ended done (exit $rc, run ${id:-none})" is_done "$rc" "$id"
  if [ -n "$id" ]; then
    set +e
    eval "$ygg grade '$id' --project '$project'" 2>&1 | tee "$v/grade.txt"
    local grc="${PIPESTATUS[0]}"
    eval "$ygg doctor --project '$project' --config '$v/factory.yaml'" >"$v/doctor.txt" 2>&1
    set -e
    check "$c: ygg grade of the finished run exited 0" is_zero "$grc"
  fi
  touch "$v/mounts.log.stop"
  wait "$watcher" || true
  trap - EXIT
  local score="$project/.factory/runs/${id:-none}/score.json" reward=none
  [ -f "$score" ] && reward="$(jq -r '.reward' "$score")"
  echo "smoke-grade: $c reward $reward"
  if [ "$c" = reference ]; then
    check "reference: reward is 1" jq -e '.reward == 1' "$score"
  else
    check "empty: reward is below 1 (it is $reward)" jq -e '(.reward | type) == "number" and .reward < 1' "$score"
  fi
  check "$c: the ledger has grade_finished twice (the node, then the command)" is_count "$project/.factory/runs/${id:-none}/ledger.jsonl" '"event": ?"grade_finished"' 2
  check "$c: no container with the label ygg.grader is left" is_empty "$(podman ps -a -q --filter label=ygg.grader 2>/dev/null || true)"
  check "$c: ygg doctor finds 0 grader containers" grep -q ' 0 grader container' "$v/doctor.txt"
  local needle
  needle="$(basename "$work")/suites"
  check "$c: the watch saw $(seen_agents "$v/mounts.log" "$(basename "$work")/$c/") agent container(s) of this run, and none held the suite folder" \
    not_held "$v/mounts.log" "$needle" "$(basename "$work")/$c/"
  if held "$v/mounts.log" "$needle"; then
    echo "PASS  $c: the watch saw the grader container hold the suite folder (the watch works)"
  else
    echo "NOTE  $c: the watch did not catch the grader container while it ran (a 1 second poll can miss it)"
  fi
  local found
  found="$(find "$v" -name 'score.json' | sort)"
  check "$c: score.json is in the run folder and nowhere else" is_same "$found" "$score"
}

if [ "$build" -eq 1 ]; then
  mkdir -p "$work/reference"
  config reference >"$work/reference/factory.yaml"
  eval "$ygg sandbox build --config '$work/reference/factory.yaml' --realm '$realm'"
fi
oneCase reference
oneCase empty

echo
echo "smoke-grade: the folder is $work"
report="$work/report.txt"
printf '%s\n' "${results[@]}" >"$report"
if [ "$clip" -eq 1 ]; then
  if command -v clip.exe >/dev/null 2>&1; then clip.exe <"$report"; echo "(copied to the clipboard)" >&2
  else echo "smoke-grade: --clip needs clip.exe (WSL); the report is in $report" >&2; fi
fi
if [ "$bad" -ne 0 ]; then echo "smoke-grade: a check failed"; exit 1; fi
echo "smoke-grade: every check passed"

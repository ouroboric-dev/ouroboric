#!/usr/bin/env bash
# Tests for ygg-proof-run.sh (v0-T290): the refusals, the filled factory.yaml, the dry run, the credentials by name
# and the suites folder that is never read.   scripts/tests/ygg-proof-run.test.sh
# Each case uses a fake `ygg` (it records its arguments and answers doctor), a fake `devcontainer`, a tiny task, a
# tiny suites folder and a fake credentials file: no engine, no model, no network. v0-T291: the fake ygg also
# answers run, grade, metrics, report and status, and logs the credential names of its environment.
# shellcheck disable=SC2329,SC2016 # check calls has and hasnt by name; the $ in the patterns is literal
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/.."
SCRIPT="$S/ygg-proof-run.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
# The script names its folder by the second, so each run that makes a project waits for the next second.
run() { sleep 1; "$@" >"$T/out" 2>&1; rc=$?; }
runq() { rm -rf "$D"/proof-*; "$@" >"$T/out" 2>&1; rc=$?; } # a refusal makes no project: no wait
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
export HOME="$T/home"; mkdir -p "$HOME"
export YGG_ENGINE_CHECK=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export YGG_BIND="$T/bind"; mkdir -p "$YGG_BIND"
export YGG_PROOF_TASK=tiny-task

D="$T/it"; mkdir -p "$D"
printf 'sandbox:\n  engine: unix:///run/user/1000/podman/podman.sock\n' >"$D/factory.yaml"
# A tiny task (key names and format as mimir's task.toml), a tiny suites folder, a fake umbrella.
TK="$T/tasks"; mkdir -p "$TK/tiny-task"
printf '# brief\n' >"$TK/tiny-task/instruction.md"
sha="$(sha256sum "$TK/tiny-task/instruction.md" | cut -d' ' -f1)"
cat >"$TK/tiny-task/task.toml" <<EOF2
schema_version = "1.4"
[task]
name = "ouroboric-dev/tiny-task"
version = "1.0.0"
[metadata]
brief_sha256 = "$sha"
suite = "v7"
EOF2
SU="$T/suites"; mkdir -p "$SU/tiny-task/v7"
YG="$T/ygg-umbrella"; mkdir -p "$YG/voluspa" "$YG/midgard-react"
# The fake credentials: made-up values that must never show up anywhere.
ENVF="$T/factory.env"
printf 'CLAUDE_CODE_OAUTH_TOKEN=fake-claude-VALUE-1\nOPENROUTER_API_KEY=fake-router-VALUE-2\n' >"$ENVF"
# Fakes: ygg records its arguments, doctor exits 0; devcontainer answers a version.
FB="$T/fakebin"; mkdir -p "$FB"
export FAKE_DIR="$T"
cat >"$FB/ygg" <<'EOF3'
#!/bin/sh
# Fake ygg (v0-T291): records its arguments and the credential NAMES in its environment, answers each subcommand.
# FAKE_RUN_RC is the exit code of `run`; FAKE_PLANT is a value it prints from run, metrics, report, grade and status.
echo "$*" >>"$FAKE_DIR/ygg.calls"
printf '%s: %s\n' "$1" "$(env | grep -E '^(CLAUDE_CODE_OAUTH_TOKEN|OPENROUTER_API_KEY)=' | cut -d= -f1 | sort | tr '\n' ' ')" >>"$FAKE_DIR/ygg.env"
proj="" prev=""
for a in "$@"; do [ "$prev" = --project ] && proj="$a"; prev="$a"; done
case "$1" in
  run)
    d="$proj/.factory/runs/RUN-1"; mkdir -p "$d"
    echo '{"event": "run_started"}' >"$d/ledger.jsonl"
    echo '{"pending":"ship-gate","pending_gate":"soft"}' >"$d/run.json"
    echo "the run runs"
    [ -z "${FAKE_PLANT:-}" ] || echo "run saw $FAKE_PLANT"
    exit "${FAKE_RUN_RC:-0}" ;;
  grade | metrics | report | status)
    echo "$1 output"
    [ -z "${FAKE_PLANT:-}" ] || echo "$1 leaked $FAKE_PLANT"
    exit 0 ;;
  *) exit 0 ;;
esac
EOF3
printf '#!/bin/sh\necho 0.89.0\n' >"$FB/devcontainer"
chmod +x "$FB/ygg" "$FB/devcontainer"
export YGG_CMD="$FB/ygg" PATH="$FB:$PATH"

BASE=(--folder "$D" --env "$ENVF" --tasks "$TK" --suites "$SU" --yggdrasil "$YG")
proof() { "$SCRIPT" "${BASE[@]}" "$@"; }
made() { find "$D" -maxdepth 1 -name 'proof-*' | head -n 1; }
refuses() { [ "$rc" -eq 2 ] && has "$1" && [ -z "$(made)" ]; }

check "the script is executable" test -x "$SCRIPT"
check "the example is there" test -f "$S/testdata/proof/factory.proof.example.yaml"

# --- refusals: exit 2, a reason, no project made
runq "$SCRIPT" "${BASE[@]}";                          check "no --name is refused" refuses "--name"
runq proof --name Bad_Name;                           check "a name outside a-z0-9- is refused" refuses "a-z0-9-"
runq proof --name ok --mode wild;                     check "a bad mode is refused" refuses "--mode"
runq proof --name ok --planner nonsense;              check "a role without a colon is refused" refuses "--planner"
runq proof --name ok --implementer gemini:flash;      check "a role with another agent is refused" refuses "--implementer"
runq proof --name ok --reviewer opencode:qwen/x;      check "an opencode model without openrouter/ is refused" refuses "--reviewer"
runq proof --name ok --reviewer 'opencode:openrouter/a b'; check "a model with a space is refused" refuses "--reviewer"
runq proof --name ok --planner 'claude-code:x
y: z';                                                check "a model with a newline is refused" refuses "--planner"
runq proof --name ok --run-turns many;                check "a cap that is not a number is refused" refuses "--run-turns"
runq proof --name ok --day-usd 1x;                    check "a usd cap that is not a number is refused" refuses "--day-usd"
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$T/nope" --suites "$SU" --yggdrasil "$YG" --name ok
check "a missing task folder is refused" refuses "no task"
cp -R "$TK" "$T/tasks2"; echo changed >>"$T/tasks2/tiny-task/instruction.md"
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$T/tasks2" --suites "$SU" --yggdrasil "$YG" --name ok
check "a changed brief is refused as not the frozen brief" refuses "not the frozen brief"
mkdir -p "$T/emptysu"
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$TK" --suites "$T/emptysu" --yggdrasil "$YG" --name ok
check "a suites folder without the task's suite is refused" refuses "tiny-task/v7"
mkdir -p "$TK/inside/tiny-task/v7"
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$TK" --suites "$TK/inside" --yggdrasil "$YG" --name ok
check "a suites folder inside the tasks folder is refused" refuses "inside"
mkdir -p "$SU/tasksin"; cp -R "$TK/tiny-task" "$SU/tasksin/"
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$SU/tasksin" --suites "$SU" --yggdrasil "$YG" --name ok
check "a tasks folder inside the suites folder is refused" refuses "inside"
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$TK" --suites "$D/hidden" --yggdrasil "$YG" --name ok
check "a missing suites folder (and so not a hidden one in the project area) is refused" refuses "tiny-task/v7"
mkdir -p "$T/p-su/tiny-task/v7"
printf 'CLAUDE_CODE_OAUTH_TOKEN=\nOPENROUTER_API_KEY=fake-router-VALUE-2\n' >"$T/env-empty"
runq proof --name ok --env "$T/env-empty";            check "a credentials file lacking a needed name is refused" refuses "CLAUDE_CODE_OAUTH_TOKEN"
check "the refusal does not print the other value" hasnt "fake-router-VALUE-2"
runq proof --name ok --env "$T/missing.env";          check "a missing credentials file is refused" refuses "credentials file"

# --- review round 1: physical paths, unsafe paths, a model ending in a colon
ln -s "$TK/inside" "$T/sl-suites"
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$TK" --suites "$T/sl-suites" --yggdrasil "$YG" --name ok
check "a suites folder that is a symlink into the tasks folder is refused" refuses "inside"
ln -s "$SU/tasksin" "$T/sl-tasks"
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$T/sl-tasks" --suites "$SU" --yggdrasil "$YG" --name ok
check "a tasks folder that is a symlink into the suites folder is refused" refuses "inside"
for odd in "a #b" "a, b" "a: b" "a}b" "a'b"; do
  mkdir -p "$T/$odd"; cp "$D/factory.yaml" "$T/$odd/"
  runq "$SCRIPT" --folder "$T/$odd" --env "$ENVF" --tasks "$TK" --suites "$SU" --yggdrasil "$YG" --name ok
  check "a --folder with '$odd' is refused, naming the flag" refuses "--folder"
done
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$TK" --suites "$SU" --yggdrasil "$T/a, b" --name ok
check "a --yggdrasil with a comma and space is refused, naming the flag" refuses "--yggdrasil"
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$T/a #b" --suites "$SU" --yggdrasil "$YG" --name ok
check "a --tasks with ' #' is refused, naming the flag" refuses "--tasks"
runq "$SCRIPT" --folder "$D" --env "$ENVF" --tasks "$TK" --suites "$T/a: b" --yggdrasil "$YG" --name ok
check "a --suites with ': ' is refused, naming the flag" refuses "--suites"
runq proof --name ok --planner claude-code:sonnet:
check "a model that ends in a colon is refused" refuses "--planner"
check "the script never enters the suites folder with cd" bash -c '! grep -E "(^|[^a-z_])cd[^#]*suites" "$1"' _ "$SCRIPT"
check "the script never evals" bash -c '! grep -E "^[^#]*\beval \"\$ygg" "$1"' _ "$SCRIPT"

# --- B-130: only the names the roles need
printf 'CLAUDE_CODE_OAUTH_TOKEN=fake-claude-VALUE-1\n' >"$T/env-claude"
printf 'OPENROUTER_API_KEY=fake-router-VALUE-2\n' >"$T/env-router"
AC=(--planner claude-code:sonnet --implementer claude-code:sonnet --reviewer claude-code:opus)
AO=(--planner opencode:openrouter/a/b --implementer opencode:openrouter/c/d --reviewer opencode:openrouter/e/f)
run proof --name allclaude --dry-run --env "$T/env-claude" "${AC[@]}"
check "all-Claude without the OpenRouter key goes through" test "$rc" -eq 0
check "all-Claude does not ask for OPENROUTER_API_KEY" hasnt OPENROUTER_API_KEY
run proof --name allopen --dry-run --env "$T/env-router" "${AO[@]}"
check "all-OpenCode without the Claude token goes through" test "$rc" -eq 0
check "all-OpenCode does not ask for CLAUDE_CODE_OAUTH_TOKEN" hasnt CLAUDE_CODE_OAUTH_TOKEN
runq proof --name mixed --env "$T/env-claude"
check "the default mix without the OpenRouter key is refused" refuses "OPENROUTER_API_KEY"

# --- the filled factory.yaml: defaults (mixed roles, so a usd line), then all-Claude (no usd line)
rm -rf "$D"/proof-*
run proof --name first --dry-run
check "a dry run with the defaults exits 0" test "$rc" -eq 0
P="$(made)"; FY="$P/factory.yaml"
check "the project is a git repository" test -d "$P/project/.git"
check "the umbrella.yaml sets root: true" grep -q '^root: true$' "$P/project/umbrella.yaml"
check "the project folder is DIR/proof-<name>-<time>/project" bash -c '[[ $1 =~ /proof-first-[0-9]{8}-[0-9]{6}$ ]]' _ "$P"
check "the config has the default mode" grep -q '^mode: key-points$' "$FY"
check "the config has the planner" grep -q 'planner: { agent: claude-code, model: sonnet }' "$FY"
check "the config has the reviewer" grep -q 'reviewer: { agent: opencode, model: openrouter/qwen/qwen3.8-27b }' "$FY"
check "the config has the run caps with usd" grep -q 'per_run: { tokens: 12000000, turns: 1500, usd: 5 }' "$FY"
check "the config has the day caps with usd" grep -q 'per_day: { tokens: 24000000, turns: 2000, usd: 10 }' "$FY"
check "the config has the tasks folder" grep -q -x "  tasks_dir: $TK" "$FY"
check "the config has the suites folder" grep -q -x "  suite_dir: $SU" "$FY"
check "the config has the realms and graphs" grep -q "dir: $YG/voluspa" "$FY"
check "the config has the engine" grep -q 'engine: unix:///run/user/1000/podman/podman.sock' "$FY"
check "no place is left to fill" bash -c '! grep -q "@[A-Z_]*@" "$1"' _ "$FY"
check "no credential value is in the config" bash -c '! grep -r -q "VALUE" "$1"' _ "$P"
check "no credential value is in the output" bash -c '! grep -q "VALUE" "$1"' _ "$T/out"
check "the plan names the graph" has "--graph"
rm -rf "$D"/proof-*
run proof --name second --dry-run --mode unattended --run-turns 10 --run-tokens 20 --day-turns 30 --day-tokens 40 "${AC[@]}"
P="$(made)"; FY="$P/factory.yaml"
check "the mode asked for is in the config" grep -q '^mode: unattended$' "$FY"
check "the caps asked for are in the config" grep -q 'per_run: { tokens: 20, turns: 10 }' "$FY"
check "the day caps asked for are in the config" grep -q 'per_day: { tokens: 40, turns: 30 }' "$FY"
check "no usd line when no role is paid" bash -c '! grep -q "usd:" "$1"' _ "$FY"
check "the reviewer asked for is in the config" grep -q 'reviewer: { agent: claude-code, model: opus }' "$FY"

# --- the dry run
rm -rf "$D"/proof-* "$T/ygg.calls"
run proof --name dry --dry-run
check "doctor ran" grep -q '^doctor ' "$T/ygg.calls"
check "ygg run never ran" bash -c '! grep -q "^run" "$1"' _ "$T/ygg.calls"
check "the dry run says nothing was started and the credentials were not loaded" has "nothing was started and the credentials were not loaded"
check "doctor was given the project and the config" grep -q -- "--project .*/project --config .*/factory.yaml" "$T/ygg.calls"

# --- the suites folder is never listed or read
SH="$T/shims"; mkdir -p "$SH"; : >"$T/shim.log"
for tool in ls find cat head tail grep sed awk du stat; do
  real="$(command -v "$tool")"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\nexec "%s" "$@"\n' "$T/shim.log" "$real" >"$SH/$tool"
  chmod +x "$SH/$tool"
done
rm -rf "$D"/proof-*
PATH="$SH:$PATH" run proof --name shims --dry-run
check "the shimmed dry run exits 0" test "$rc" -eq 0
check "the shims were called" test -s "$T/shim.log"
check "no reader was called with the suites folder" bash -c '! grep -q -F -- "$1" "$2"' _ "$SU" "$T/shim.log"
check "no reader was called with a folder inside the suites folder" bash -c '! grep -q -F -- "tiny-task/v7" "$1"' _ "$T/shim.log"

# --- v0-T291: the run, the grade and the evidence
calls() { grep -v '^status ' "$T/ygg.calls" | cut -d' ' -f1 | paste -sd, -; }
fresh() { rm -rf "$D"/proof-* "$T/ygg.calls" "$T/ygg.env"; }
runit() { fresh; FAKE_RUN_RC="$1" run proof --name go "${@:2}"; }
RUND() { find "$D" -maxdepth 1 -name 'proof-go-*' | head -n 1; }
runit 0
check "exit 0: the script exits 0" test "$rc" -eq 0
check "exit 0: doctor, run, grade, metrics, report in that order" test "$(calls)" = "doctor,run,grade,metrics,report"
check "run.txt holds the run's output" grep -q 'the run runs' "$(RUND)/run.txt"
check "report.txt holds the metrics and the report" bash -c 'grep -q "metrics output" "$1" && grep -q "report output" "$1"' _ "$(RUND)/report.txt"
check "the run's output was shown" has "the run runs"
check "the exit code is printed" has "exit code 0"
runit 5
check "exit 5: the script exits 5" test "$rc" -eq 5
check "exit 5: doctor, run, grade, metrics, report" test "$(calls)" = "doctor,run,grade,metrics,report"
for c in 1 3 4 124; do
  runit "$c"
  check "exit $c: the script exits $c" test "$rc" -eq "$c"
  check "exit $c: no grade, but metrics and report" test "$(calls)" = "doctor,run,metrics,report"
  check "exit $c: the exit code is printed" has "exit code $c"
done
runit 3
check "exit 3: the output ends with the approve command" bash -c 'tail -n 1 "$1" | grep -q -F "ygg-engine.sh run" && tail -n 1 "$1" | grep -q -F "approve RUN-1 ship-gate"' _ "$T/out"
check "exit 3: the approve command names the project" bash -c 'tail -n 1 "$1" | grep -q -F -- "--project"' _ "$T/out"
runit 4
check "exit 4: the output says how to resume" bash -c 'tail -n 1 "$1" | grep -q -F "resume RUN-1"' _ "$T/out"
runit 0 --mode unattended
RL="$(grep '^run ' "$T/ygg.calls")"
check "run gets the task's instruction.md as the brief" bash -c 'grep -q -F -- "--brief $1/tiny-task/instruction.md" <<<"$2"' _ "$TK" "$RL"
check "run gets --graph software" bash -c 'grep -q -F -- "--graph software" <<<"$1"' _ "$RL"
check "run gets the mode asked for" bash -c 'grep -q -F -- "--mode unattended" <<<"$1"' _ "$RL"
check "run gets the filled config and the project" bash -c 'grep -q -E -- "--config [^ ]*/proof-go-[0-9-]+/factory.yaml" <<<"$1" && grep -q -E -- "--project [^ ]*/project" <<<"$1"' _ "$RL"
check "no credential value is in any argument" bash -c '! grep -q VALUE "$1"' _ "$T/ygg.calls"
check "run has both credentials in its environment" grep -q -x 'run: CLAUDE_CODE_OAUTH_TOKEN OPENROUTER_API_KEY ' "$T/ygg.env"
check "doctor (the script's own shell) has no credential" grep -q -x 'doctor: ' "$T/ygg.env"
runit 0 --baseline OLD-RUN
check "--baseline: metrics --compare follows metrics" test "$(grep -E '^metrics' "$T/ygg.calls" | paste -sd'|' -)" = "metrics RUN-1 --project $(RUND)/project|metrics --compare OLD-RUN RUN-1 --project $(RUND)/project"
check "--baseline: the comparison is printed as given, with no verdict of the script" bash -c '! grep -q -i -E "better|worse|improv|verdict" "$1"' _ "$T/out"
runit 3 --baseline OLD-RUN
check "--baseline with exit 3: the output still ends with the approve command" bash -c 'tail -n 1 "$1" | grep -q -F "approve RUN-1"' _ "$T/out"
fresh
FAKE_PLANT=fake-claude-VALUE-1 FAKE_RUN_RC=0 run proof --name go
check "a planted credential value is not in the printed output" hasnt "fake-claude-VALUE-1"
check "a planted credential value is not in report.txt" bash -c '! grep -q -F fake-claude-VALUE-1 "$1"' _ "$(RUND)/report.txt"
check "a planted credential value is not in run.txt" bash -c '! grep -q -F fake-claude-VALUE-1 "$1"' _ "$(RUND)/run.txt"
check "the planted value was replaced, not dropped" grep -q 'REDACTED' "$(RUND)/report.txt"
fresh
FAKE_RUN_RC=0 run proof --name go --build
check "--build: sandbox build --all --config runs after doctor and before the run" test "$(calls)" = "doctor,sandbox,run,grade,metrics,report"
check "--build: the build call has --all and --config" grep -q -E '^sandbox build --all --config [^ ]*/factory.yaml$' "$T/ygg.calls"
fresh
FAKE_RUN_RC=0 run proof --name go --dry-run
check "dry run: run and the build still never run" bash -c '! grep -q "^run\|^grade" "$1"' _ "$T/ygg.calls"
fresh
PATH="$SH:$PATH" FAKE_RUN_RC=0 run proof --name go --build
check "the shimmed full run exits 0" test "$rc" -eq 0
check "the shimmed full run called the readers" test -s "$T/shim.log"
check "the full run called no reader with the suites folder" bash -c '! grep -q -F -- "$1" "$2"' _ "$SU" "$T/shim.log"
check "the full run called no reader with a folder inside the suites folder" bash -c '! grep -q -F -- "tiny-task/v7" "$1"' _ "$T/shim.log"

[ "$fail" -eq 0 ] && echo "all ok"
exit "$fail"

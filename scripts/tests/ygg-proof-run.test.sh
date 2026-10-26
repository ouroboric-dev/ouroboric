#!/usr/bin/env bash
# Tests for ygg-proof-run.sh (v0-T290): the refusals, the filled factory.yaml, the dry run, the credentials by name
# and the suites folder that is never read.   scripts/tests/ygg-proof-run.test.sh
# Each case uses a fake `ygg` (it records its arguments and answers doctor), a fake `devcontainer`, a tiny task, a
# tiny suites folder and a fake credentials file: no engine, no model, no network. v0-T291: the fake ygg also
# answers run, grade, metrics, report and status, and logs the credential names of its environment. The ouroboric
# review: it also answers approve, resume and metrics --compare (which reads both runs from the one project it gets).
# shellcheck disable=SC2329,SC2016 # check calls has and hasnt by name; the $ in the patterns is literal
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The whole test runs under env -i, with PATH, HOME and GOPATH in its own folder (hermetic.sh).
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$HERE/hermetic.sh"
HERMETIC_TOOLS="git python3" hermetic_enter "$@"
S="$HERE/.."
SCRIPT="$S/ygg-proof-run.sh"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
# The script names its folder by the second, so each run that makes a project waits for the next second.
pathok() { hermetic_path_ok "$PATH" || { echo "FAIL the test's PATH leaves its folder: $PATH"; exit 3; }; }
run() { pathok; sleep 1; "$@" >"$T/out" 2>&1; rc=$?; }
runq() { pathok; rm -rf "$D"/proof-*; "$@" >"$T/out" 2>&1; rc=$?; } # a refusal makes no project: no wait
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
export HOME="$T/home"; mkdir -p "$HOME"
umask 022 # the caller's umask: the project and what ygg makes follow it; only the script's own files are private
mode_is() { [ "$(stat -c %a "$2")" = "$1" ]; } # MODE PATH
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
# FAKE_CONT_RC is the exit code of `approve`, `resume` and `reject`. `record` prints the path of record.json.
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
    [ -z "${FAKE_BAD:-}" ] || printf 'bad \377 byte %s\n' "${FAKE_PLANT:-}"
    # FAKE_CHILD: the run starts a child (SIGINT at its default, as a real tool's) that must not outlive it.
    if [ -n "${FAKE_CHILD:-}" ]; then
      python3 -I -c 'import os, signal, sys, time; signal.signal(signal.SIGINT, signal.SIG_DFL); open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(20)' "$FAKE_DIR/child.pid" &
    fi
    if [ -n "${FAKE_SLEEP:-}" ]; then echo $$ >"$FAKE_DIR/run.pid"; exec sleep "$FAKE_SLEEP"; fi
    # FAKE_TRAP: the run shuts down on INT, HUP or TERM as ygg does: it prints for a second, then ends stopped (3).
    if [ -n "${FAKE_TRAP:-}" ]; then
      for s in INT HUP TERM; do
        trap "echo 'the run got $s; shutting down'; i=0; while [ \$i -lt 5 ]; do echo \"shutdown line \$i\"; sleep 0.2; i=\$((i+1)); done; echo 'the run shut down'; exit 3" "$s"
      done
      echo $$ >"$FAKE_DIR/run.pid"
      while :; do sleep 0.2; done
    fi
    exit "${FAKE_RUN_RC:-0}" ;;
  approve | resume | reject)
    echo "$1 runs"
    [ -z "${FAKE_PLANT:-}" ] || echo "$1 saw $FAKE_PLANT"
    exit "${FAKE_CONT_RC:-0}" ;;
  metrics)
    # The comparison reads both runs from the one project it is given, as ygg does.
    if [ "$2" = --compare ]; then
      for r in "$3" "$4"; do
        [ -f "$proj/.factory/runs/$r/run.json" ] && [ -f "$proj/.factory/runs/$r/ledger.jsonl" ] || { echo "ygg: project $proj has no run $r" >&2; exit 2; }
      done
      echo "compare $3 to $4: $(cat "$proj/.factory/runs/$3/run.json")"
      exit 0
    fi
    echo "$1 output"
    [ -z "${FAKE_PLANT:-}" ] || echo "$1 leaked $FAKE_PLANT"
    exit 0 ;;
  grade | report | status)
    echo "$1 output"
    [ -z "${FAKE_PLANT:-}" ] || echo "$1 leaked $FAKE_PLANT"
    exit 0 ;;
  record)
    echo "$proj/.factory/runs/$2/record.json"
    exit 0 ;;
  sandbox)
    if [ -n "${FAKE_BUILD_SLEEP:-}" ]; then echo $$ >"$FAKE_DIR/build.pid"; exec sleep "$FAKE_BUILD_SLEEP"; fi
    exit 0 ;;
  *) exit 0 ;;
esac
EOF3
REALTIMEOUT="$(command -v timeout)"
printf '#!/bin/sh\necho "$*" >>"%s/timeout.args"\nexec "%s" "$@"\n' "$T" "$REALTIMEOUT" >"$FB/timeout"
chmod +x "$FB/timeout"
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
AO=(--planner opencode:openrouter/a/b --implementer opencode:openrouter/c/d --reviewer opencode:openrouter/e/f --retro-agent opencode --retro-model openrouter/g/h)
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
check "the config has the reviewer" grep -q 'reviewer: { agent: opencode, model: openrouter/qwen/qwen3.8-27b, reasoning: medium }' "$FY"
check "the config has the run caps with usd" grep -q 'per_run: { tokens: 12000000, turns: 1500, usd: 5 }' "$FY"
check "the config has the day caps with usd" grep -q 'per_day: { tokens: 24000000, turns: 2000, usd: 10 }' "$FY"
check "the config has the tasks folder" grep -q -x "  tasks_dir: $TK" "$FY"
check "the config has the suites folder" grep -q -x "  suite_dir: $SU" "$FY"
check "the config has the realms and graphs" grep -q "dir: $YG/voluspa" "$FY"
check "the config has the engine" grep -q 'engine: unix:///run/user/1000/podman/podman.sock' "$FY"
check "no place is left to fill" bash -c '! grep -q "@[A-Z_]*@" "$1"' _ "$FY"
check "proof.meta is private (600)" bash -c '[ "$(stat -c %a "$1")" = 600 ]' _ "$P/proof.meta"
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
check "the reviewer asked for is in the config" grep -q 'reviewer: { agent: claude-code, model: opus, reasoning: medium }' "$FY"

# --- gallery-runtime T28: the reviewer's reasoning effort (F2)
rm -rf "$D"/proof-* "$T/ygg.calls"
run proof --name reason --dry-run
P="$(made)"; FY="$P/factory.yaml"
check "the reviewer role asks for reasoning medium by default" grep -q 'reviewer: { agent: opencode, model: openrouter/qwen/qwen3.8-27b, reasoning: medium }' "$FY"
check "the planner and the implementer have no reasoning" bash -c '! grep -E "^  (planner|implementer):" "$1" | grep -q reasoning' _ "$FY"
check "the plan says reviewer AGENT:MODEL (reasoning medium)" has "reviewer opencode:openrouter/qwen/qwen3.8-27b (reasoning medium)"
check "the config with reasoning passes ygg doctor" grep -q -- "^doctor --project .*/project --config $FY\$" "$T/ygg.calls"
check "the config has no place left to fill" bash -c '! grep -q "@[A-Z_]*@" "$1"' _ "$FY"
rm -rf "$D"/proof-*
run proof --name reasonoff --dry-run --reviewer-reasoning off "${AC[@]}"
P="$(made)"
check "--reviewer-reasoning off writes off, for a claude-code reviewer too" grep -q 'reviewer: { agent: claude-code, model: opus, reasoning: off }' "$P/factory.yaml"
check "--reviewer-reasoning off shows in the plan" has "(reasoning off)"
for v in low high; do
  rm -rf "$D"/proof-*; run proof --name reasonv --dry-run --reviewer-reasoning "$v"
  check "--reviewer-reasoning $v writes $v" grep -q "reasoning: $v }" "$(made)/factory.yaml"
done
runq proof --name ok --reviewer-reasoning extreme;    check "a reasoning outside low, medium, high and off is refused" refuses "--reviewer-reasoning"
runq proof --name ok --reviewer-reasoning 'low }';    check "a reasoning with YAML characters is refused" refuses "--reviewer-reasoning"

# --- local-models LM-T13: opencode:local/<name> with --models FILE
printf 'models: []\n' >"$T/models.yaml"; : >"$T/env-none"
LR=(--planner claude-code:sonnet --implementer claude-code:sonnet --reviewer opencode:local/qwen3.8-27b)
run proof --name local --dry-run --env "$T/env-claude" --models "$T/models.yaml" "${LR[@]}"
P="$(made)"
check "a local reviewer with --models: exit 0" test "$rc" -eq 0
check "the config has the local reviewer, with no reasoning" grep -q -x '  reviewer: { agent: opencode, model: local/qwen3.8-27b }' "$P/factory.yaml"
check "the config has models.file" grep -q -x "  file: $T/models.yaml" "$P/factory.yaml"
check "the models section is the file's last" bash -c 'tail -n 2 "$1" | head -n 1 | grep -q -x "models:"' _ "$P/factory.yaml"
check "no usd line when the other roles are claude-code" bash -c '! grep -q "usd:" "$1"' _ "$P/factory.yaml"
check "no reasoning in the roles" bash -c '! grep -q "^  [a-z]*: {.*reasoning" "$1"' _ "$P/factory.yaml"
check "it does not ask for OPENROUTER_API_KEY" hasnt OPENROUTER_API_KEY
check "it says the reasoning is left out" has "the reviewer is a local model, so its reasoning is left out"
check "the plan says no reasoning" has "reviewer opencode:local/qwen3.8-27b (no reasoning: a local model sets none)"
check "ygg doctor ran on it" grep -q -- "^doctor --project .*/project --config $P/factory.yaml\$" "$T/ygg.calls"
check "proof.meta keeps the local reviewer" grep -q '^reviewer opencode:local/qwen3.8-27b$' "$P/proof.meta"
runq proof --name local --dry-run --env "$T/env-claude" "${LR[@]}"
check "a local role without --models is refused" refuses "--models FILE"
runq proof --name local --dry-run --env "$T/env-claude" --models "$T/nope.yaml" "${LR[@]}"
check "a models file that is missing is refused" refuses "no such file"
runq proof --name local --dry-run --env "$T/env-claude" --models "$T/models.yaml" "${AC[@]}"
check "--models with no local role is refused" refuses "no role is on one"
runq proof --name local --dry-run --env "$T/env-claude" --models "$T/models.yaml" --planner claude-code:sonnet --implementer claude-code:sonnet --reviewer opencode:local/Bad
check "a bad local name is refused" refuses "local/<name>"
rm -rf "$D"/proof-*
(cd "$T" && run proof --name localrel --dry-run --env "$T/env-claude" --models models.yaml "${LR[@]}")
check "a relative --models path is made absolute" grep -q -x "  file: $T/models.yaml" "$(made)/factory.yaml"
rm -rf "$D"/proof-*
run proof --name localmix --dry-run --env "$T/env-claude" --models "$T/models.yaml" --reviewer-reasoning high --planner claude-code:sonnet --implementer claude-code:sonnet --reviewer opencode:local/qwen3.8-27b
check "a local reviewer ignores --reviewer-reasoning" bash -c '! grep -q "^  [a-z]*: {.*reasoning" "$1"' _ "$(made)/factory.yaml"
rm -rf "$D"/proof-*
run proof --name localpaid --dry-run --models "$T/models.yaml" --planner opencode:local/a --implementer opencode:local/b
check "a role on OpenRouter beside local ones: exit 0" test "$rc" -eq 0
check "it keeps the usd lines" grep -q 'per_run: { tokens: 12000000, turns: 1500, usd: 5 }' "$(made)/factory.yaml"
check "and the reviewer's reasoning" grep -q 'reviewer: { agent: opencode, model: openrouter/qwen/qwen3.8-27b, reasoning: medium }' "$(made)/factory.yaml"
runq proof --name localpaid --dry-run --env "$T/env-claude" --models "$T/models.yaml" --planner opencode:local/a --implementer opencode:local/b
check "and asks for OPENROUTER_API_KEY" refuses "OPENROUTER_API_KEY"
run proof --name alllocal --dry-run --env "$T/env-none" --models "$T/models.yaml" --planner opencode:local/a --implementer opencode:local/b --reviewer opencode:local/c --retro-agent opencode --retro-model local/d
check "all-local roles need no credentials: exit 0" test "$rc" -eq 0
check "all-local asks for neither name" bash -c '! grep -q -e CLAUDE_CODE_OAUTH_TOKEN -e OPENROUTER_API_KEY "$1"' _ "$T/out"

# --- the dry run
rm -rf "$D"/proof-* "$T/ygg.calls"
run proof --name dry --dry-run
check "doctor ran" grep -q '^doctor ' "$T/ygg.calls"
check "ygg run never ran" bash -c '! grep -q "^run" "$1"' _ "$T/ygg.calls"
check "the dry run says nothing was started and the credentials were not loaded" has "nothing was started and the credentials were not loaded"
check "doctor was given the project and the config" grep -q -- "--project .*/project --config .*/factory.yaml" "$T/ygg.calls"

# --- the stale-binary guard: a ygg from PATH (not YGG_CMD) must have build facts (ygg-build.sh) that name the HEAD of
# the umbrella's odin
mkdir -p "$YG/odin"; git -C "$YG/odin" init -q -b main; printf 'x\n' >"$YG/odin/f"; git -C "$YG/odin" add f
git -C "$YG/odin" -c user.name=t -c user.email=t@example.invalid commit -q -m odin
head12="$(git -C "$YG/odin" rev-parse --short=12 HEAD)"
facts() { printf 'format: 1\nodin: %s\nsha256: %s\n' "$2" "$(sha256sum "$1" | cut -d' ' -f1)" >"$1.build.txt"; } # BINARY ODIN_COMMIT
build_cmd="run: $(cd "$S" && pwd)/ygg-build.sh --yggdrasil $YG"
rm -f "$FB/ygg.build.txt"
runq env -u YGG_CMD "$SCRIPT" "${BASE[@]}" --name guard --dry-run
check "guard: a dry run with a ygg with no build facts is not refused" test "$rc" -eq 0
check "guard: it prints STALE and says to run the build script" has "proof-run: ygg guard: STALE: the ygg at $FB/ygg has no build facts"
check "guard: it gives the whole build command and says the dry run did not refuse" has "$build_cmd (a dry run: not refused)"
: >"$T/ygg.calls"
runq env -u YGG_CMD "$SCRIPT" "${BASE[@]}" --name guard
check "guard: a real run with no build facts is refused, and makes nothing" refuses "$build_cmd"
check "guard: the refusal names --any-ygg" has "--any-ygg"
check "guard: no ygg verb ran before the refusal" test ! -s "$T/ygg.calls"
facts "$FB/ygg" 000000000000
runq env -u YGG_CMD "$SCRIPT" "${BASE[@]}" --name guard
check "guard: a binary from another commit is refused, with both commits" refuses "built from odin 000000000000, but the checkout $YG/odin is at $head12"
runq env -u YGG_CMD "$SCRIPT" "${BASE[@]}" --name guard --any-ygg --dry-run
check "guard: --any-ygg passes a stale binary and says so" bash -c '[ "$1" -eq 0 ] && grep -q -F "proof-run: ygg guard: skipped (--any-ygg)" "$2"' _ "$rc" "$T/out"
: >"$T/ygg.calls"
run env -u YGG_CMD "$SCRIPT" "${BASE[@]}" --name guard --any-ygg
check "guard: a real run with --any-ygg and a stale binary runs, and says it skipped the check" bash -c '[ "$1" -eq 0 ] && grep -q -F "proof-run: ygg guard: skipped (--any-ygg)" "$2" && grep -q "^run " "$3"' _ "$rc" "$T/out" "$T/ygg.calls"
rm -rf "$D"/proof-*
facts "$FB/ygg" "$head12"
runq env -u YGG_CMD "$SCRIPT" "${BASE[@]}" --name guard --dry-run
check "guard: a binary built from odin's HEAD passes" bash -c '[ "$1" -eq 0 ] && grep -q -F "proof-run: ygg guard: ok" "$2"' _ "$rc" "$T/out"
cp "$FB/ygg" "$T/ygg.keep"; printf '# rebuilt by hand\n' >>"$FB/ygg"
runq env -u YGG_CMD "$SCRIPT" "${BASE[@]}" --name guard
check "guard: a binary changed after its facts were written is refused" refuses "is not the binary ygg-build.sh wrote"
mv "$T/ygg.keep" "$FB/ygg"
runq "$SCRIPT" "${BASE[@]}" --name guard --dry-run
check "guard: YGG_CMD is not guarded" bash -c '[ "$1" -eq 0 ] && ! grep -q "ygg guard" "$2"' _ "$rc" "$T/out"
rm -f "$FB/ygg.build.txt"; rm -rf "$D"/proof-* "$YG/odin"

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
check "exit 0: doctor, run, metrics, report in that order" test "$(calls)" = "doctor,run,metrics,report,record"
check "run.txt holds the run's output" grep -q 'the run runs' "$(RUND)/run.txt"
check "report.txt holds the metrics and the report" bash -c 'grep -q "metrics output" "$1" && grep -q "report output" "$1"' _ "$(RUND)/report.txt"
check "the run's output was shown" has "the run runs"
check "the exit code is printed" has "exit code 0"
runit 5
check "exit 5: the script exits 5" test "$rc" -eq 5
check "exit 5: doctor, run, metrics, report" test "$(calls)" = "doctor,run,metrics,report,record"
for c in 1 3 4 124; do
  runit "$c"
  check "exit $c: the script exits $c" test "$rc" -eq "$c"
  case "$c" in
    3 | 4) check "exit $c: no grade (the run graded itself), but metrics and report" test "$(calls)" = "doctor,run,metrics,report" ;;
    *) check "exit $c: no grade; doctor after the abnormal end, then metrics and report" test "$(calls)" = "doctor,run,doctor,metrics,report" ;;
  esac
  check "exit $c: the exit code is printed" has "exit code $c"
done
runit 3
check "exit 3: the output ends with the script's own --continue --approve command" bash -c 'tail -n 1 "$1" | grep -q -F "ygg-proof-run.sh --continue RUN-1 --approve ship-gate"' _ "$T/out"
check "exit 3: the --continue command names the folder and the credentials file" bash -c 'tail -n 1 "$1" | grep -q -F -- "--folder $2" && tail -n 1 "$1" | grep -q -F -- "--env $3"' _ "$T/out" "$D" "$ENVF"
check "exit 3: the raw approve command is still there, as a fallback" bash -c 'grep -F "ygg-engine.sh run" "$1" | grep -q -F "approve RUN-1 ship-gate --project"' _ "$T/out"
runit 4
check "exit 4: the output ends with the script's own --continue --resume command" bash -c 'tail -n 1 "$1" | grep -q -F "ygg-proof-run.sh --continue RUN-1 --resume"' _ "$T/out"
check "exit 4: the raw resume command is still there, as a fallback" bash -c 'grep -F "ygg-engine.sh run" "$1" | grep -q -F "resume RUN-1 --project"' _ "$T/out"
runit 0 --mode unattended
RL="$(grep '^run ' "$T/ygg.calls")"
check "run gets the task's instruction.md as the brief" bash -c 'grep -q -F -- "--brief $1/tiny-task/instruction.md" <<<"$2"' _ "$TK" "$RL"
check "run gets --graph software" bash -c 'grep -q -F -- "--graph software" <<<"$1"' _ "$RL"
check "run gets the mode asked for" bash -c 'grep -q -F -- "--mode unattended" <<<"$1"' _ "$RL"
check "run gets the filled config and the project" bash -c 'grep -q -E -- "--config [^ ]*/proof-go-[0-9-]+/factory.yaml" <<<"$1" && grep -q -E -- "--project [^ ]*/project" <<<"$1"' _ "$RL"
check "no credential value is in any argument" bash -c '! grep -q VALUE "$1"' _ "$T/ygg.calls"
check "run has both credentials in its environment" grep -q -x 'run: CLAUDE_CODE_OAUTH_TOKEN OPENROUTER_API_KEY ' "$T/ygg.env"
check "doctor (the script's own shell) has no credential" grep -q -x 'doctor: ' "$T/ygg.env"
# A baseline is a run of an earlier proof run, in its own proof folder and so its own project.
OLD=20200101-000000-abcdef
plant_base() { # [ID [FOLDER]]: a finished run in another proof folder
  local b="$D/${2:-proof-old-20200101-000000}/project/.factory/runs/${1:-$OLD}"
  mkdir -p "$b"
  echo '{"pending":"","marker":"BASELINE-MARK"}' >"$b/run.json"
  echo '{"event": "run_started"}' >"$b/ledger.jsonl"
}
fresh; plant_base; FAKE_RUN_RC=0 run proof --name go --baseline "$OLD"
check "--baseline: metrics --compare follows metrics, on a project that holds both runs" test "$(grep -E '^metrics' "$T/ygg.calls" | paste -sd'|' -)" = "metrics RUN-1 --project $(RUND)/project|metrics --compare $OLD RUN-1 --project $(RUND)/compare"
check "--baseline: the baseline in another proof folder is found and compared" grep -q -F "compare $OLD to RUN-1: {\"pending\":\"\",\"marker\":\"BASELINE-MARK\"}" "$(RUND)/report.txt"
check "--baseline: the comparison is printed as given, with no verdict of the script" bash -c '! grep -q -i -E "better|worse|improv|verdict" "$1"' _ "$T/out"
fresh; plant_base; FAKE_RUN_RC=3 run proof --name go --baseline "$OLD"
check "--baseline with exit 3: the output still ends with the --continue command" bash -c 'tail -n 1 "$1" | grep -q -F -- "--continue RUN-1 --approve ship-gate"' _ "$T/out"
fresh
FAKE_PLANT=fake-claude-VALUE-1 FAKE_RUN_RC=0 run proof --name go
check "a planted credential value is not in the printed output" hasnt "fake-claude-VALUE-1"
check "a planted credential value is not in report.txt" bash -c '! grep -q -F fake-claude-VALUE-1 "$1"' _ "$(RUND)/report.txt"
check "a planted credential value is not in run.txt" bash -c '! grep -q -F fake-claude-VALUE-1 "$1"' _ "$(RUND)/run.txt"
check "the planted value was replaced, not dropped" grep -q 'REDACTED' "$(RUND)/report.txt"
fresh
FAKE_RUN_RC=0 run proof --name go --build
check "--build: sandbox build --all --config runs after doctor and before the run" test "$(calls)" = "doctor,sandbox,run,metrics,report,record"
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

# --- v0-T291 review: least privilege, any byte, the run's exit code, signals, umask
runit 0
check "least privilege: only run has the credentials" bash -c 'grep -q -x "run: CLAUDE_CODE_OAUTH_TOKEN OPENROUTER_API_KEY " "$1" && ! grep -E "^(grade|metrics|report|status|doctor): ." "$1"' _ "$T/ygg.env"
check "least privilege: metrics, report and status ran without them" bash -c 'for s in metrics report status; do grep -q -x "$s: " "$1" || exit 1; done' _ "$T/ygg.env"
fresh; plant_base; FAKE_RUN_RC=0 run proof --name go --build --baseline "$OLD"
check "least privilege: sandbox build and metrics --compare ran without them" bash -c 'grep -q -x "sandbox: " "$1" && ! grep -E "^(sandbox|metrics): ." "$1"' _ "$T/ygg.env"
fresh
LC_ALL=C.UTF-8 FAKE_BAD=1 FAKE_PLANT=fake-claude-VALUE-1 FAKE_RUN_RC=3 run proof --name go
check "an invalid UTF-8 byte does not stop the run: its exit code 3 is kept" test "$rc" -eq 3
check "an invalid byte: the planted value is gone from run.txt" bash -c '! grep -a -q -F fake-claude-VALUE-1 "$1"' _ "$(RUND)/run.txt"
check "an invalid byte: the byte survives in run.txt" python3 -I -c 'import sys; sys.exit(0 if b"bad \xff byte [REDACTED]" in open(sys.argv[1],"rb").read() else 1)' "$(RUND)/run.txt"
check "an invalid byte: the report is still made" grep -q 'metrics output' "$(RUND)/report.txt"
# A filter that fails: the run's exit code and the hint stay.
FP="$T/failpy"; mkdir -p "$FP"; REALPY="$(command -v python3)"
printf '#!/bin/sh\ncase "$*" in *"-u -c"*) exit 1 ;; esac\nexec "%s" "$@"\n' "$REALPY" >"$FP/python3"; chmod +x "$FP/python3"
fresh
PATH="$FP:$PATH" FAKE_PLANT=fake-claude-VALUE-1 FAKE_RUN_RC=3 run proof --name go
check "a failing output filter: the script still exits with the run's code 3" test "$rc" -eq 3
check "a failing output filter: the output ends with the --continue command" bash -c 'tail -n 1 "$1" | grep -q -F -- "--continue RUN-1 --approve ship-gate"' _ "$T/out"
check "a failing output filter: no credential value is printed" hasnt "fake-claude-VALUE-1"
check "a failing output filter: the metrics call still happened" grep -q '^metrics ' "$T/ygg.calls"
# Signals: TERM to the script reaches the run.
fresh; rm -f "$T/run.pid"
sleep 1
FAKE_SLEEP=20 FAKE_RUN_RC=0 "$SCRIPT" "${BASE[@]}" --name go >"$T/out" 2>&1 &
spid=$!
for _ in $(seq 1 50); do [ -s "$T/run.pid" ] && break; sleep 0.1; done
rpid="$(cat "$T/run.pid" 2>/dev/null || echo 0)"
check "the fake run is running before the signal" kill -0 "$rpid"
kill -TERM "$spid" 2>/dev/null
for _ in $(seq 1 50); do kill -0 "$spid" 2>/dev/null || break; sleep 0.1; done
check "TERM to the script ends the script" bash -c '! kill -0 "$1" 2>/dev/null' _ "$spid"
check "TERM to the script ends the run too" bash -c '! kill -0 "$1" 2>/dev/null' _ "$rpid"
kill -KILL "$spid" "$rpid" 2>/dev/null; wait "$spid" 2>/dev/null
check "the run's files are private (600)" mode_is 600 "$(RUND)/run.txt"
# Only the script's own files are private: the project and what ygg makes in it keep the caller's umask (022 here).
runit 0
check "umask: the project folder follows the caller's umask (755)" mode_is 755 "$(RUND)/project"
check "umask: the run folder ygg made follows it (755)" mode_is 755 "$(RUND)/project/.factory/runs/RUN-1"
check "umask: a file ygg made follows it (644)" mode_is 644 "$(RUND)/project/.factory/runs/RUN-1/run.json"
check "umask: the project's git files follow it (644)" mode_is 644 "$(RUND)/project/umbrella.yaml"
for f in proof.meta run.txt report.txt run.rc; do check "umask: the script's own $f is private (600)" mode_is 600 "$(RUND)/$f"; done
check "the exit line labels 137 and 141" bash -c 'grep -q "137" "$1" && grep -q "141" "$1"' _ "$SCRIPT"

# --- v0-T291 review round 2: the process group, a stop before the run, a filter that fails closed
rm -f "$T/timeout.args"; fresh
FAKE_RUN_RC=0 run proof --name go --dry-run
DRYL="$(grep 'would run: timeout' "$T/out" | head -n 1)"
check "the dry run shows the timeout command without --foreground" bash -c '[[ $1 == *"timeout --signal=INT --kill-after=2m 8h "* && $1 != *foreground* ]]' _ "$DRYL"
fresh
FAKE_RUN_RC=0 run proof --name go
check "the timeout that ran is the one the dry run showed" test "$(head -n 1 "$T/timeout.args" | cut -d' ' -f1-3)" = "--signal=INT --kill-after=2m 8h"
check "timeout runs without --foreground (it gets its own process group)" bash -c '! grep -q foreground "$1"' _ "$T/timeout.args"
check "the script header shows the same timeout command" bash -c 'grep -q -F "timeout --signal=INT --kill-after=2m WALL" "$1" && ! grep -q "timeout --foreground" "$1"' _ "$SCRIPT"
# TERM while the sandbox build sleeps: the run is never started.
fresh; rm -f "$T/build.pid" "$T/run.pid"; sleep 1
FAKE_BUILD_SLEEP=20 FAKE_RUN_RC=0 "$SCRIPT" "${BASE[@]}" --name go --build >"$T/out" 2>&1 &
spid=$!
for _ in $(seq 1 50); do [ -s "$T/build.pid" ] && break; sleep 0.1; done
bpid="$(cat "$T/build.pid" 2>/dev/null || echo 0)"
check "the fake build is running before the signal" kill -0 "$bpid"
kill -TERM "$spid" 2>/dev/null
for _ in $(seq 1 50); do kill -0 "$spid" 2>/dev/null || break; sleep 0.1; done
kill -KILL "$spid" 2>/dev/null || true # never wait without a bound
wait "$spid" 2>/dev/null; rc=$?
check "TERM during the build: the script exits 143" test "$rc" -eq 143
check "TERM during the build: ygg run is never called" bash -c '! grep -q "^run " "$1"' _ "$T/ygg.calls"
check "TERM during the build: the output says the run was not started" has "not started"
check "TERM during the build: the build is gone" bash -c '! kill -0 "$1" 2>/dev/null' _ "$bpid"
kill -KILL "$spid" "$bpid" 2>/dev/null
# An env file that cannot be loaded: the filter withholds, the run is not started, no value is shown.
printf 'CLAUDE_CODE_OAUTH_TOKEN=fake-claude-VALUE-1\nOPENROUTER_API_KEY=fake-router-VALUE-2\nif then (\n' >"$T/env-broken"
fresh
FAKE_PLANT=fake-claude-VALUE-1 FAKE_RUN_RC=0 run proof --name go --env "$T/env-broken"
check "an env file that cannot be sourced: no credential value is printed" bash -c '! grep -q VALUE "$1"' _ "$T/out"
check "an env file that cannot be sourced: the output is withheld, and it says so" has "withheld"
check "an env file that cannot be sourced: ygg run is not called" bash -c '! grep -q "^run " "$1"' _ "$T/ygg.calls"
check "an env file that cannot be sourced: the exit code is not 0" test "$rc" -ne 0
check "an env file that cannot be sourced: no credential value in the kept files" bash -c '! grep -r -a -q VALUE "$1"' _ "$(RUND)"

# --- v0-T291 review round 3: a bad credentials line is never echoed; INT stops the build too
printf 'CLAUDE_CODE_OAUTH_TOKEN=fake-claude-VALUE-1 (\nOPENROUTER_API_KEY=fake-router-VALUE-2\n' >"$T/env-badline"
fresh
FAKE_PLANT=fake-claude-VALUE-1 FAKE_RUN_RC=0 run proof --name go --env "$T/env-badline"
check "a bad credentials line: the value is nowhere in stdout or stderr" bash -c '! grep -q VALUE "$1"' _ "$T/out"
check "a bad credentials line: the value is in no kept file" bash -c '! grep -r -a -q VALUE "$1"' _ "$(RUND)"
check "a bad credentials line: it says the file could not be read" has "credentials file could not be read"
check "a bad credentials line: ygg run is not called" bash -c '! grep -q "^run " "$1"' _ "$T/ygg.calls"
# INT during the build (the script is started with SIGINT at its default, as a terminal would leave it).
fresh; rm -f "$T/build.pid" "$T/run.pid"; sleep 1
FAKE_BUILD_SLEEP=20 FAKE_RUN_RC=0 python3 -I -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])' "$SCRIPT" "${BASE[@]}" --name go --build >"$T/out" 2>&1 &
spid=$!
for _ in $(seq 1 50); do [ -s "$T/build.pid" ] && break; sleep 0.1; done
bpid="$(cat "$T/build.pid" 2>/dev/null || echo 0)"
check "the fake build is running before INT" kill -0 "$bpid"
kill -INT "$spid" 2>/dev/null
# The build must stop because of the signal, within 5 s (the fake build sleeps 20 s and ignores INT).
for _ in $(seq 1 50); do kill -0 "$bpid" 2>/dev/null || break; sleep 0.1; done
check "INT during the build: the build is gone within 5 s" bash -c '! kill -0 "$1" 2>/dev/null' _ "$bpid"
for _ in $(seq 1 50); do kill -0 "$spid" 2>/dev/null || break; sleep 0.1; done
check "INT during the build: the script is gone within 10 s" bash -c '! kill -0 "$1" 2>/dev/null' _ "$spid"
kill -KILL "$bpid" 2>/dev/null
kill -KILL "$spid" 2>/dev/null || true # never wait without a bound
wait "$spid" 2>/dev/null; rc=$?
check "INT during the build: the script exits 130" test "$rc" -eq 130
check "INT during the build: ygg run is never called" bash -c '! grep -q "^run " "$1"' _ "$T/ygg.calls"
check "INT during the build: the output says the run was not started" has "not started"
check "INT during the build: the build is gone" bash -c '! kill -0 "$1" 2>/dev/null' _ "$bpid"
kill -KILL "$spid" "$bpid" 2>/dev/null

# --- the ouroboric review (C1): a terminal's Ctrl-C and hang-up reach the script's whole process group
# The script is started as a terminal starts it: in its own process group, with SIGINT and SIGHUP at their defaults.
startg() { # ARGS...: the script in the background; spid is its pid and its process group
  python3 -I -c 'import os, signal, sys; os.setpgid(0, 0); signal.signal(signal.SIGINT, signal.SIG_DFL); signal.signal(signal.SIGHUP, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])' "$SCRIPT" "${BASE[@]}" "$@" >"$T/out" 2>&1 &
  spid=$!
}
waitfor() { for _ in $(seq 1 50); do [ -s "$1" ] && break; sleep 0.1; done; } # FILE: at most 5 s
gone() { for _ in $(seq 1 150); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.1; done; return 1; } # PID: at most 15 s
pgid_of() { ps -o pgid= -p "$1" 2>/dev/null | tr -d ' '; }
reap() { # what a failing case leaves: the script's group and the fake run's group (timeout's)
  kill -KILL -- "-$spid" 2>/dev/null; [ -z "${rpg:-}" ] || kill -KILL -- "-$rpg" 2>/dev/null
  kill -KILL "$spid" 2>/dev/null || true # never wait without a bound
  wait "$spid" 2>/dev/null
}
for sig in INT HUP; do
  fresh; rm -f "$T/run.pid"; sleep 1
  FAKE_TRAP=1 startg --name go
  waitfor "$T/run.pid"; rpid="$(cat "$T/run.pid" 2>/dev/null || echo 0)"; rpg="$(pgid_of "$rpid")"
  check "$sig to the group: the fake run is running before the signal" kill -0 "$rpid"
  sleep 0.5
  kill -s "$sig" -- "-$spid" 2>/dev/null
  run_alive=1 rc=999
  if gone "$spid"; then
    kill -0 "$rpid" 2>/dev/null || run_alive=0 # the moment the script has ended, the run must be over
    wait "$spid" 2>/dev/null; rc=$?
  fi
  check "$sig to the group: the script ends (within 15 s)" test "$rc" -ne 999
  check "$sig to the group: the script does not end before the run" test "$run_alive" -eq 0
  check "$sig to the group: the script's exit code is the run's (3)" test "$rc" -eq 3
  check "$sig to the group: the run's shutdown lines are in run.txt" bash -c 'grep -q "shutdown line 4" "$1" && grep -q "the run shut down" "$1"' _ "$(RUND)/run.txt"
  check "$sig to the group: the run got the signal once" test "$(grep -c "the run got" "$(RUND)/run.txt")" = 1
  check "$sig to the group: report.txt is made after the run" grep -q 'metrics output' "$(RUND)/report.txt"
  reap
done
# A terminal that closes: the kernel hangs up the session (the script leads it here), and every later write to the
# terminal fails. The script must still stop the run, keep its exit code and make the report. FIRST is a signal that
# comes just before, while the run is still shutting down (a Ctrl-C to the script's group, a TERM to the script), or
# "none".
cat >"$T/pty.py" <<'PY2'
import os, pty, select, signal, sys, time
first, ready, argv = sys.argv[1], sys.argv[2], sys.argv[3:]
pid, fd = pty.fork()
if pid == 0:
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGHUP, signal.SIG_DFL)
    os.execv(argv[0], argv)
def drain(secs):
    end = time.time() + secs
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                os.read(fd, 4096)
            except OSError:
                return
end = time.time() + 5
while time.time() < end and not os.path.exists(ready):
    drain(0.1)
drain(0.5)
if first != "none":
    if first == "INT":
        os.killpg(pid, signal.SIGINT)  # a Ctrl-C reaches the script's whole process group (it leads its own)
    else:
        os.kill(pid, getattr(signal, "SIG" + first))  # a TERM is sent to the script
    drain(0.3)  # the run is shutting down (it takes a second) when the terminal closes
os.close(fd)  # the terminal closes
end = time.time() + 15
while time.time() < end:
    p, status = os.waitpid(pid, os.WNOHANG)
    if p:
        print("rc=%d" % os.waitstatus_to_exitcode(status))
        sys.exit(0)
    time.sleep(0.1)
os.kill(pid, signal.SIGKILL)
os.waitpid(pid, 0)
print("rc=still-running")
PY2
for first in none INT TERM; do
  case "$first" in none) what="a closed terminal" ;; *) what="$first, then a closed terminal" ;; esac
  fresh; rm -f "$T/run.pid"; sleep 1
  FAKE_TRAP=1 timeout 60 python3 -I "$T/pty.py" "$first" "$T/run.pid" "$SCRIPT" "${BASE[@]}" --name go >"$T/pty.out" 2>&1
  rpid="$(cat "$T/run.pid" 2>/dev/null || echo 0)"; rpg="$(pgid_of "$rpid")"
  check "$what: the script ends with the run's exit code (3)" grep -q -x 'rc=3' "$T/pty.out"
  check "$what: the run is stopped, no process is left" bash -c '[ "$1" != 0 ] && ! kill -0 "$1" 2>/dev/null && { [ -z "$2" ] || ! pgrep -g "$2" >/dev/null; }' _ "$rpid" "$rpg"
  check "$what: the run's shutdown lines are in run.txt" grep -q "the run shut down" "$(RUND)/run.txt"
  check "$what: report.txt is made" grep -q 'metrics output' "$(RUND)/report.txt"
  check "$what: what the script prints after it is kept in hangup.txt" bash -c 'grep -q "exit code 3" "$1" && grep -q -F -- "--continue RUN-1" "$1"' _ "$(RUND)/hangup.txt"
  check "$what: hangup.txt, run.stop and run.hup are private (600)" bash -c 'for f in hangup.txt run.hup; do [ "$(stat -c %a "$1/$f")" = 600 ] || exit 1; done; [ ! -e "$1/run.stop" ] || [ "$(stat -c %a "$1/run.stop")" = 600 ]' _ "$(RUND)"
  [ -z "$rpg" ] || kill -KILL -- "-$rpg" 2>/dev/null
done

# --- the ouroboric review (T2): the real wall clock ends the run and what it started
fresh; rm -f "$T/run.pid" "$T/child.pid"; sleep 1
FAKE_SLEEP=20 FAKE_CHILD=1 timeout 60 "$SCRIPT" "${BASE[@]}" --name go --wall 2s >"$T/out" 2>&1; rc=$?
rpid="$(cat "$T/run.pid" 2>/dev/null || echo 0)"; cpid="$(cat "$T/child.pid" 2>/dev/null || echo 0)"
check "--wall 2s: the script exits 124" test "$rc" -eq 124
check "--wall 2s: the fake run is gone" bash -c '[ "$1" != 0 ] && ! kill -0 "$1" 2>/dev/null' _ "$rpid"
check "--wall 2s: the child the run started is gone" bash -c '[ "$1" != 0 ] && ! kill -0 "$1" 2>/dev/null' _ "$cpid"
kill -KILL "$rpid" "$cpid" 2>/dev/null

# --- the ouroboric review (I2): after an abnormal end, ygg doctor stops what the run left
runit 137
check "exit 137: the script exits 137" test "$rc" -eq 137
check "exit 137: doctor runs after the run, before the evidence" test "$(calls)" = "doctor,run,doctor,metrics,report"
check "exit 137: that doctor gets the project and the config" bash -c 'sed -n 3p "$1" | grep -q -E -- "^doctor --project [^ ]*/proof-go-[0-9-]+/project --config [^ ]*/proof-go-[0-9-]+/factory.yaml$"' _ "$T/ygg.calls"
check "exit 137: that doctor has no credential" test "$(grep -c -x 'doctor: ' "$T/ygg.env")" = 2
check "exit 137: the doctor's output is in report.txt" grep -q -F '## ygg doctor' "$(RUND)/report.txt"
runit 0
check "exit 0: no doctor after the run" test "$(calls)" = "doctor,run,metrics,report,record"

# --- the ouroboric review (C2): a baseline is found in its own proof folder, or refused before anything starts
nothing_started() { [ "$rc" -eq 2 ] && [ ! -s "$T/ygg.calls" ] && [ -z "$(find "$D" -maxdepth 1 -name 'proof-go-*')" ]; }
fresh; plant_base; run proof --name go --baseline 20200101-000000-ffffff
check "a baseline no proof folder holds: exit 2, nothing started, no folder made" nothing_started
check "a baseline no proof folder holds: it says so" has "no proof folder under"
fresh; plant_base; plant_base "$OLD" proof-old2-20200102-000000; run proof --name go --baseline "$OLD"
check "a baseline two proof folders hold: exit 2, nothing started, no folder made" nothing_started
check "a baseline two proof folders hold: it says so" has "2 proof folders under"
fresh; plant_base; run proof --name go --dry-run --baseline "$OLD"
check "the dry run names the baseline it found and its folder" bash -c 'grep -F "baseline run $2" "$1" | grep -q -F "proof-old-20200101-000000"' _ "$T/out" "$OLD"

# --- the ouroboric review (I1): --continue continues a stopped or paused run inside the script
CBASE=(--folder "$D" --env "$ENVF")
cont() { "$SCRIPT" "${CBASE[@]}" "$@"; }
runc() { pathok; "$@" >"$T/out" 2>&1; rc=$?; } # a continuation makes no folder: no wait
clearlogs() { rm -f "$T/ygg.calls" "$T/ygg.env" "$T/timeout.args"; }
fresh; plant_base; FAKE_RUN_RC=3 run proof --name go --baseline "$OLD"; W="$(RUND)"; clearlogs
FAKE_PLANT=fake-claude-VALUE-1 runc cont --continue RUN-1 --approve ship-gate --note 'looks right'
check "--continue --approve after 3: exit 0, the continuation's code" test "$rc" -eq 0
check "--continue --approve: doctor, approve, metrics, the compare, report" test "$(calls)" = "doctor,approve,metrics,metrics,report,record"
check "--continue --approve: approve gets the run, the gate, the project and the note" grep -q -x -F "approve RUN-1 ship-gate --project $W/project --note looks right" "$T/ygg.calls"
check "--continue --approve: it runs under the same timeout" bash -c 'head -n 1 "$1" | grep -q -F -- "--signal=INT --kill-after=2m 8h $2 approve RUN-1 ship-gate"' _ "$T/timeout.args" "$FB/ygg"
check "--continue: only approve has the credentials" bash -c 'grep -q -x "approve: CLAUDE_CODE_OAUTH_TOKEN OPENROUTER_API_KEY " "$1" && [ "$(grep -c -v -E "^approve: " "$1")" = "$(grep -c -E "^[a-z]+: $" "$1")" ]' _ "$T/ygg.env"
check "--continue: the output is added to the folder's run.txt" bash -c 'grep -q "the run runs" "$1" && grep -q "approve runs" "$1"' _ "$W/run.txt"
check "--continue: a planted value is filtered from run.txt and the output" bash -c '! grep -q -F fake-claude-VALUE-1 "$1" && ! grep -q -F fake-claude-VALUE-1 "$2" && grep -q REDACTED "$1"' _ "$W/run.txt" "$T/out"
check "--continue: the recorded baseline is compared" grep -q -x -F "metrics --compare $OLD RUN-1 --project $W/compare" "$T/ygg.calls"
check "--continue: the report is added to report.txt" bash -c '[ "$(grep -c "^# proof run go: run RUN-1" "$1")" = 2 ] && grep -q "^## ygg metrics" "$1"' _ "$W/report.txt"
check "--continue: run.txt and report.txt stay private, the compare folder is private" bash -c '[ "$(stat -c %a "$1/run.txt")" = 600 ] && [ "$(stat -c %a "$1/report.txt")" = 600 ] && [ "$(stat -c %a "$1/compare")" = 700 ]' _ "$W"
check "--continue: no new proof folder" test "$(find "$D" -maxdepth 1 -name 'proof-go-*' | wc -l)" = 1
fresh; FAKE_RUN_RC=4 run proof --name go; W="$(RUND)"; clearlogs
FAKE_CONT_RC=3 runc cont --continue RUN-1 --resume
check "--continue --resume after 4: resume gets the run and the project" grep -q -x -F "resume RUN-1 --project $W/project" "$T/ygg.calls"
check "--continue --resume ending 3: no grade, metrics and report" test "$(calls)" = "doctor,resume,metrics,report"
check "--continue --resume ending 3: the exit code is 3" test "$rc" -eq 3
check "--continue --resume ending 3: the output ends with the next --continue command" bash -c 'tail -n 1 "$1" | grep -q -F "ygg-proof-run.sh --continue RUN-1 --approve ship-gate"' _ "$T/out"
clearlogs; FAKE_CONT_RC=0 runc cont --continue RUN-1 --resume
check "--continue --resume ending 0: doctor, resume, metrics, report" test "$(calls)" = "doctor,resume,metrics,report,record"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --dry-run
check "--continue --dry-run: exit 0, approve never called" bash -c '[ "$1" -eq 0 ] && ! grep -q "^approve" "$2"' _ "$rc" "$T/ygg.calls"
check "--continue --dry-run: it shows the command under the timeout" bash -c 'grep "would run: timeout --signal=INT --kill-after=2m 8h" "$1" | grep -q -F "approve RUN-1 ship-gate --project"' _ "$T/out"
refusesc() { [ "$rc" -eq 2 ] && has "$1" && [ ! -s "$T/ygg.calls" ]; } # exit 2, the reason, nothing started
clearlogs; runc cont --continue NOPE-RUN --resume;                  check "--continue with no such run: refused before anything starts" refusesc "no proof folder under"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --resume; check "--continue with --approve and --resume: refused" refusesc "only one"
clearlogs; runc cont --continue RUN-1;                              check "--continue with no action: refused" refusesc "--approve GATE, --reject GATE --reason TEXT or --resume"
clearlogs; runc cont --approve ship-gate;                           check "--approve without --continue: refused" refusesc "go with --continue"
clearlogs; runc cont --continue RUN-1 --resume --note hi;           check "--note without --approve: refused" refusesc "--note goes with --approve"
clearlogs; runc cont --continue RUN-1 --resume --name other;        check "--continue with a setup flag: refused" refusesc "keeps the config"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --note $'a\nb'; check "--note with a control character: refused" refusesc "control character"
clearlogs; LC_ALL=C runc cont --continue RUN-1 --approve ship-gate --note $'a\xe2\x80\xa8b'; check "--note with U+2028: refused" refusesc "control character"
clearlogs; LC_ALL=C runc cont --continue RUN-1 --approve ship-gate --note $'a\xe2\x80\xa9b'; check "--note with U+2029: refused" refusesc "control character"
clearlogs; LC_ALL=C runc cont --continue RUN-1 --approve ship-gate --note $'a\xc2\x85b'; check "--note with a C1 control (NEL): refused" refusesc "control character"
clearlogs; LC_ALL=C runc cont --continue RUN-1 --approve ship-gate --note $'a\xc2\x9fb'; check "--note with the last C1 control: refused" refusesc "control character"
clearlogs; LC_ALL=C runc cont --continue RUN-1 --approve ship-gate --note $'a\xc2\xa0b'; check "--note with U+00A0 (not a control): kept" bash -c "! grep -q 'control character' '$T/out'"
clearlogs; runc cont --continue .. --resume;                        check "--continue .. is not a run id" refusesc "not a run id"
clearlogs; runc cont --continue RUN-1 --resume --reviewer-reasoning low; check "--continue refuses --reviewer-reasoning as a setup flag" refusesc "keeps the config"
# --- gallery-runtime T29: --reject (F3), run as --approve is run
fresh; plant_base; FAKE_RUN_RC=3 run proof --name go --baseline "$OLD"; W="$(RUND)"; clearlogs
FAKE_PLANT=fake-claude-VALUE-1 runc cont --continue RUN-1 --reject ship-gate --reason 'the gallery has no empty state'
check "--reject after 3: exit 0, the continuation's code" test "$rc" -eq 0
check "--reject: doctor, reject, metrics, the compare, report" test "$(calls)" = "doctor,reject,metrics,metrics,report,record"
check "--reject: ygg reject runs once, with the run, the gate, the reason and the project" bash -c '[ "$(grep -c "^reject " "$1")" = 1 ] && grep -q -x -F "reject RUN-1 ship-gate --reason the gallery has no empty state --project $2/project" "$1"' _ "$T/ygg.calls" "$W"
check "--reject: it runs under the same timeout" bash -c 'head -n 1 "$1" | grep -q -F -- "--signal=INT --kill-after=2m 8h $2 reject RUN-1 ship-gate"' _ "$T/timeout.args" "$FB/ygg"
check "--reject: only reject has the credentials" bash -c 'grep -q -x "reject: CLAUDE_CODE_OAUTH_TOKEN OPENROUTER_API_KEY " "$1" && [ "$(grep -c -v -E "^reject: " "$1")" = "$(grep -c -E "^[a-z]+: $" "$1")" ]' _ "$T/ygg.env"
check "--reject: the output is added to the folder's run.txt" bash -c 'grep -q "the run runs" "$1" && grep -q "reject runs" "$1"' _ "$W/run.txt"
check "--reject: a planted value is filtered from run.txt and the output" bash -c '! grep -q -F fake-claude-VALUE-1 "$1" && ! grep -q -F fake-claude-VALUE-1 "$2" && grep -q REDACTED "$1"' _ "$W/run.txt" "$T/out"
check "--reject: the report header records the reviewer's reasoning" grep -q "reviewer opencode:openrouter/qwen/qwen3.8-27b (reasoning medium); brief SHA-256" "$W/report.txt"
check "--reject: the report says what was continued" bash -c 'grep -q "(continued: reject ship-gate)" "$1"' _ "$W/report.txt"
clearlogs; FAKE_CONT_RC=3 runc cont --continue RUN-1 --reject ship-gate --reason 'again'
check "--reject ending 3: the exit code is 3, with no grade" bash -c '[ "$1" -eq 3 ] && [ "$2" = "doctor,reject,metrics,metrics,report" ]' _ "$rc" "$(calls)"
check "--reject ending 3: step 9 prints the --reject form beside the --approve one" bash -c 'grep -F -- "--continue RUN-1 --reject ship-gate --reason \"...\"" "$1" | grep -q -F -- "--folder $2" && tail -n 1 "$1" | grep -q -F -- "--continue RUN-1 --approve ship-gate"' _ "$T/out" "$D"
check "--reject ending 3: step 9 words the rejection as conditional" has "If ygg offered a rejection above"
check "--reject ending 3: the raw fallback names ygg reject" bash -c 'grep -F "ygg-engine.sh run" "$1" | grep -q -F "reject RUN-1 ship-gate --reason"' _ "$T/out"
clearlogs; runc cont --continue RUN-1 --reject ship-gate --reason 'no' --dry-run
check "--reject --dry-run: exit 0, reject never called" bash -c '[ "$1" -eq 0 ] && ! grep -q "^reject" "$2"' _ "$rc" "$T/ygg.calls"
check "--reject --dry-run: it shows the command under the timeout" bash -c 'grep "would run: timeout --signal=INT --kill-after=2m 8h" "$1" | grep -q -F "reject RUN-1 ship-gate --reason no --project"' _ "$T/out"
clearlogs; runc cont --continue RUN-1 --reject ship-gate;                                   check "--reject without --reason: refused" refusesc "--reject needs --reason"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --reason why;                     check "--reason without --reject: refused" refusesc "--reason goes with --reject"
clearlogs; runc cont --continue RUN-1 --resume --reason why;                                check "--reason with --resume: refused" refusesc "--reason goes with --reject"
clearlogs; runc cont --continue RUN-1 --reject ship-gate --approve ship-gate --reason why; check "--reject with --approve: refused" refusesc "only one"
clearlogs; runc cont --continue RUN-1 --reject ship-gate --resume --reason why;             check "--reject with --resume: refused" refusesc "only one"
clearlogs; runc cont --continue RUN-1 --reject ship-gate --reason why --note hi;            check "--note with --reject: refused" refusesc "--note goes with --approve"
clearlogs; runc cont --continue RUN-1 --reject ship-gate --reason '   ';                    check "--reject with a blank reason: refused" refusesc "--reason is blank"
clearlogs; runc cont --continue RUN-1 --reject ship-gate --reason $'a\nb';                  check "--reject with a control character in the reason: refused" refusesc "control character"
clearlogs; LC_ALL=C runc cont --continue RUN-1 --reject ship-gate --reason $'a\xe2\x80\xa8b';              check "--reject with U+2028 in the reason: refused" refusesc "control character"
clearlogs; LC_ALL=C runc cont --continue RUN-1 --reject ship-gate --reason $'a\xe2\x80\xa9b';              check "--reject with U+2029 in the reason: refused" refusesc "control character"
clearlogs; LC_ALL=C runc cont --continue RUN-1 --reject ship-gate --reason $'a\xc2\x85b'; check "--reject with a C1 control in the reason: refused" refusesc "control character"
clearlogs; runc cont --continue RUN-1 --reject 'a b' --reason why;                         check "--reject with a bad gate name: refused" refusesc "not a gate name"
clearlogs; runc cont --reject ship-gate --reason why;                                       check "--reject without --continue: refused" refusesc "go with --continue"
clearlogs; runc cont --reason why;                                                          check "--reason without --continue: refused" refusesc "go with --continue"
fresh; FAKE_RUN_RC=4 run proof --name go; W="$(RUND)"; clearlogs
cp "$W/proof.meta" "$T/meta.keep"
grep -v '^reviewer_reasoning ' "$T/meta.keep" >"$W/proof.meta"
clearlogs; runc cont --continue RUN-1 --resume --dry-run
check "--continue on a proof.meta without reviewer_reasoning goes on (exit 0)" test "$rc" -eq 0
check "--continue on such a folder prints the unset form" has "(reasoning unset: a folder from before --reviewer-reasoning)"
sed 's/^reviewer_reasoning .*/reviewer_reasoning extreme/' "$T/meta.keep" >"$W/proof.meta"
clearlogs; runc cont --continue RUN-1 --resume --dry-run
check "--continue on a proof.meta with a bad reviewer_reasoning is refused" refusesc "reviewer reasoning"
cp "$T/meta.keep" "$W/proof.meta"

# --- typed-boundaries T29: decisions files, the retrospective role, `ygg score`
printf 'decisions: []\n' >"$T/dec.yaml"
fresh; plant_base; FAKE_RUN_RC=3 run proof --name go --baseline "$OLD"; W="$(RUND)"; clearlogs
runc cont --continue RUN-1 --approve ship-gate --decisions "$T/dec.yaml"
check "--approve --decisions: exit 0" test "$rc" -eq 0
check "--approve --decisions: ygg approve gets the file, after the project" grep -q -x -F "approve RUN-1 ship-gate --project $W/project --decisions $T/dec.yaml" "$T/ygg.calls"
check "--approve --decisions: the plan says so" has "approve ship-gate"
clearlogs; (cd "$T" && runc cont --continue RUN-1 --approve ship-gate --decisions dec.yaml)
check "--decisions with a relative path: ygg gets the absolute one" grep -q -x -F "approve RUN-1 ship-gate --project $W/project --decisions $T/dec.yaml" "$T/ygg.calls"
clearlogs; runc cont --continue RUN-1 --reject ship-gate --decisions "$T/dec.yaml"
check "--reject --decisions with no --reason: valid, ygg reject gets the file" grep -q -x -F "reject RUN-1 ship-gate --project $W/project --decisions $T/dec.yaml" "$T/ygg.calls"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --decisions "$T/dec.yaml" --note hi
check "--decisions with --note: refused before ygg is called" bash -c '[ "$1" -eq 2 ] && ! test -s "$2" && grep -q -F -- "replaces --note and --reason" "$3"' _ "$rc" "$T/ygg.calls" "$T/out"
clearlogs; runc cont --continue RUN-1 --reject ship-gate --decisions "$T/dec.yaml" --reason why
check "--decisions with --reason: refused before ygg is called" bash -c '[ "$1" -eq 2 ] && ! test -s "$2" && grep -q -F -- "replaces --note and --reason" "$3"' _ "$rc" "$T/ygg.calls" "$T/out"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --decisions "$T/nope.yaml";  check "--decisions with a missing file: refused" refusesc "nope.yaml"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --decisions "$T";            check "--decisions with a folder: refused" refusesc "--decisions"
clearlogs; runc cont --continue RUN-1 --resume --decisions "$T/dec.yaml";              check "--decisions with --resume: refused" refusesc "--decisions goes with --approve or --reject"
clearlogs; runc cont --decisions "$T/dec.yaml";                                         check "--decisions without --continue: refused" refusesc "go with --continue"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --decisions;                  check "--decisions with no value: usage" bash -c '[ "$1" -eq 2 ]' _ "$rc"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --decisions "$T/dec.yaml" --dry-run
check "--decisions --dry-run: the command shows the file" bash -c 'grep "would run: timeout" "$1" | grep -q -F -- "--decisions $2"' _ "$T/out" "$T/dec.yaml"
clearlogs; mkdir -p "$T/odd dir"; printf 'decisions: []\n' >"$T/odd dir/it's here.yaml"
runc cont --continue RUN-1 --approve ship-gate --decisions "$T/odd dir/it's here.yaml"
check "--decisions with a space and a single quote: ygg approve gets it as one argument" bash -c '[ "$(grep -c "^approve " "$1")" = 1 ] && grep -q -x -F "approve RUN-1 ship-gate --project $2/project --decisions $3" "$1" && grep -q -x -F "approve: CLAUDE_CODE_OAUTH_TOKEN OPENROUTER_API_KEY " "$4"' _ "$T/ygg.calls" "$W" "$T/odd dir/it's here.yaml" "$T/ygg.env"
check "--decisions with a space and a single quote: the argument is one, by its count" bash -c 'n=$(grep -F "approve RUN-1" "$1" | wc -l); [ "$n" = 1 ]' _ "$T/ygg.calls"
clearlogs; runc cont --continue RUN-1 --reject ship-gate --decisions "$T/odd dir/it's here.yaml"
check "--decisions with a space and a single quote: ygg reject gets it as one argument" grep -q -x -F "reject RUN-1 ship-gate --project $W/project --decisions $T/odd dir/it's here.yaml" "$T/ygg.calls"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --decisions "$T/odd dir/it's here.yaml" --dry-run
check "--decisions with a space and a single quote: the dry run prints it quoted" has "it\\'s\\ here.yaml"
printf 'x\n' >"$T/ctl"$'\n'"name.yaml"
clearlogs; runc cont --continue RUN-1 --approve ship-gate --decisions "$T/ctl"$'\n'"name.yaml"
check "--decisions with a control character in the path: refused" refusesc "--decisions has a control character"

rm -rf "$D"/proof-*; run proof --name retro --dry-run
FY="$(made)/factory.yaml"
check "the config has the retrospective role, claude-code:opus by default" grep -q '^  retrospective: { agent: claude-code, model: opus }$' "$FY"
check "the plan names the retrospective" has "retrospective claude-code:opus"
check "proof.meta keeps the retrospective" grep -q -x 'retrospective claude-code:opus' "$(made)/proof.meta"
rm -rf "$D"/proof-*; run proof --name retro2 --dry-run --retro-agent opencode --retro-model openrouter/a/b
P="$(made)"
check "--retro-agent and --retro-model are written to the config" grep -q '^  retrospective: { agent: opencode, model: openrouter/a/b }$' "$P/factory.yaml"
check "an opencode retrospective makes the caps count usd" grep -q 'per_run: { tokens: 12000000, turns: 1500, usd: 5 }' "$P/factory.yaml"
rm -rf "$D"/proof-*; run proof --name retro3 --dry-run --env "$T/env-claude" "${AC[@]}" --retro-agent opencode --retro-model openrouter/a/b
check "an opencode retrospective needs OPENROUTER_API_KEY" bash -c '[ "$1" -eq 2 ] && grep -q OPENROUTER_API_KEY "$2"' _ "$rc" "$T/out"
runq proof --name ok --retro-agent gemini;                 check "a retro agent that is not an adapter is refused" refuses "--retro"
runq proof --name ok --retro-model 'a b';                  check "a retro model with a space is refused" refuses "--retro"
runq proof --name ok --retro-agent opencode;               check "an opencode retro agent with the default model is refused" refuses "--retro"
runq proof --name ok --retro-model 'x
y: z';                                                      check "a retro model with a newline is refused" refuses "--retro"
fresh; plant_base; FAKE_RUN_RC=3 run proof --name go; W="$(RUND)"
clearlogs; runc cont --continue RUN-1 --resume --retro-model sonnet; check "--continue refuses --retro-model as a setup flag" refusesc "keeps the config"
grep -v '^retrospective ' "$W/proof.meta" >"$T/meta.old"; cp "$T/meta.old" "$W/proof.meta"
clearlogs; runc cont --continue RUN-1 --resume --dry-run;  check "--continue on a proof.meta without a retrospective goes on" test "$rc" -eq 0

fresh; run proof --name go; W="$(RUND)"
check "exit 0: the script never calls ygg grade: the run graded itself" bash -c '! grep -q "^grade" "$1"' _ "$T/ygg.calls"
check "exit 0: ygg record runs after the report" test "$(calls)" = "doctor,run,metrics,report,record"
check "exit 0: the ready ygg score line has the real run id" has 'ygg score RUN-1 --score N --well "…" --wrong "…"'
check "exit 0: the path of record.json is printed" has "$W/project/.factory/runs/RUN-1/record.json"
check "exit 0: the score line is in the output, with the project" has "--project $W/project"
for c in 1 3 4 124; do
  fresh; FAKE_RUN_RC=$c run proof --name go
  check "exit $c: no score line and no record" bash -c '! grep -q "ygg score" "$1" && ! grep -q "^record" "$2"' _ "$T/out" "$T/ygg.calls"
done
fresh; FAKE_RUN_RC=5 run proof --name go; W="$(RUND)"
check "exit 5: the ready ygg score line has the real run id" has 'score RUN-1 --score N --well "…" --wrong "…"'
check "exit 5: the path of record.json is printed" has "$W/project/.factory/runs/RUN-1/record.json"
fresh; plant_base; FAKE_RUN_RC=3 run proof --name go; W="$(RUND)"; clearlogs
runc cont --continue RUN-1 --approve ship-gate
check "--continue ending 0: the score line and the record path are printed" bash -c 'grep -q -F "ygg score RUN-1 --score N" "$1" && grep -q -F "$2/project/.factory/runs/RUN-1/record.json" "$1"' _ "$T/out" "$W"
clearlogs; FAKE_CONT_RC=5 runc cont --continue RUN-1 --approve ship-gate
check "--continue ending 5: record, the score line and the record path" bash -c 'grep -q "^record RUN-1" "$1" && grep -q -F "score RUN-1 --score N" "$2" && grep -q -F "RUN-1/record.json" "$2"' _ "$T/ygg.calls" "$T/out"
clearlogs; FAKE_CONT_RC=3 runc cont --continue RUN-1 --approve ship-gate
check "--continue ending 3: no score line" bash -c '! grep -q "ygg score" "$1"' _ "$T/out"

hermetic_done
[ "$fail" -eq 0 ] && echo "all ok"
exit "$fail"

#!/usr/bin/env bash
# Tests for ygg-proof-run.sh (v0-T290): the refusals, the filled factory.yaml, the dry run, the credentials by name
# and the suites folder that is never read.   scripts/tests/ygg-proof-run.test.sh
# Each case uses a fake `ygg` (it records its arguments and answers doctor), a fake `devcontainer`, a tiny task, a
# tiny suites folder and a fake credentials file: no engine, no model, no network, never `ygg run`.
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
printf '#!/bin/sh\necho "$*" >>"%s/ygg.calls"\nexit 0\n' "$T" >"$FB/ygg"
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

[ "$fail" -eq 0 ] && echo "all ok"
exit "$fail"

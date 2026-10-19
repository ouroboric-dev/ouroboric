#!/usr/bin/env bash
# Tests for ygg-smoke-grade.sh, ygg-smoke-real.sh and ygg-cost.sh.   scripts/tests/ygg-smoke-grade.test.sh
# A fake `ygg`, a fake `podman` and a fake `devcontainer` stand in for the real tools: no model, no engine, no
# network, no money. The task folder is a small made-up mimir with a made-up public suite.
# shellcheck disable=SC2329,SC2016 # check calls has and hasnt by name; the $ in the patterns is literal
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/.."
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
run() { "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
export HOME="$T/home"; mkdir -p "$HOME"
export YGG_ENGINE_CHECK=0 # the engine environment has its own test (ygg-engine.test.sh)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# A made-up mimir: the task, its public suite and its reference solution.
M="$T/mimir"; mkdir -p "$M/smoke-notes/sample-suite/tests" "$M/smoke-notes/sample-suite/reference"
printf '[metadata]\nsuite = "v1"\n' >"$M/smoke-notes/task.toml"
printf '# brief\n' >"$M/smoke-notes/instruction.md"
printf '{"schema":"ygg.suite/v1"}\n' >"$M/smoke-notes/sample-suite/tests/manifest.json"
printf '#!/bin/bash\n' >"$M/smoke-notes/sample-suite/tests/test.sh"
printf '#!/bin/bash\nexec node server.js\n' >"$M/smoke-notes/sample-suite/reference/start.sh"
printf 'console.log("it has a \\"quote\\" and a tab\\there");\n' >"$M/smoke-notes/sample-suite/reference/server.js"
printf '# reference\n' >"$M/smoke-notes/sample-suite/reference/README.md"
# A made-up odin: the realm and the example config of the real run.
O="$T/odin/testdata/smoke-grade"; mkdir -p "$O"
printf 'name: smoke-grade\n' >"$O/pack.yaml"
cat >"$O/factory.real.example.yaml" <<'EOF'
mode: unattended
roles:
  implementer: { agent: claude-code, model: sonnet }
  reviewer: { agent: opencode, model: openrouter/deepseek/deepseek-v4-flash }
budget:
  per_run: { tokens: 400000, turns: 100, usd: 3 }
  per_day: { tokens: 1000000, turns: 200, usd: 6 }
sandbox:
  engine: @ENGINE@
  mounts:
    - { host: @FOLDER@, engine: @BIND@ }
grader:
  tasks_dir: @TASKS@
  suite_dir: @SUITES@
  timeout: 10m
  memory: none
  cpus: 0
EOF

# The fake ygg. `run` makes a run folder with a ledger and a score.json (reward 1 when the scripted answers hold
# the reference solution, else 0); FAKE_LEAK puts a second score.json in the project; FAKE_RUN_SLEEP makes it hang.
mkdir -p "$T/bin" "$T/it"
cat >"$T/bin/ygg" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${FAKE_ARGS_LOG:-/dev/null}"
proj='' cfg=''
while [ $# -gt 0 ]; do case "$1" in --project) proj="$2" ;; --config) cfg="$2" ;; esac; shift; done
case "$FAKE_VERB" in
  doctor)
    [ -z "${FAKE_DOCTOR_RC:-}" ] || { echo "ERROR graders: 2 grader container(s) of ygg runs"; exit "$FAKE_DOCTOR_RC"; }
    echo "OK    graders: 0 grader container(s) of ygg runs" ;;
  status) echo "status:   done" ;;
  build) echo "built" ;;
  run)
    [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || echo "the credentials were loaded" >>"${FAKE_ARGS_LOG:-/dev/null}"
    [ -z "${FAKE_RUN_SLEEP:-}" ] || exec sleep "$FAKE_RUN_SLEEP"
    id=20261018-000000-000001
    mkdir -p "$proj/.factory/runs/$id"
    script="$(grep -o 'script: [^ ,}]*' "$cfg" | head -n 1 | sed 's/^script: //')"
    reward=0
    [ -z "$script" ] || ! grep -q 'server.js' "$script" || reward=1
    [ -z "${FAKE_REWARD:-}" ] || reward="$FAKE_REWARD"
    printf '{"schema":"ygg.score/v1","reward":%s,"task":"smoke-notes","task_version":"1.0.0","fail_to_pass":{"passed":6,"total":6},"pass_to_pass":{"passed":1,"total":1}}\n' "$reward" >"$proj/.factory/runs/$id/score.json"
    [ -z "${FAKE_LEAK:-}" ] || cp "$proj/.factory/runs/$id/score.json" "$proj/score.json"
    {
      echo '{"seq":1,"event":"node_finished","ygg.node.id":"build","gen_ai.usage.input_tokens":1000,"gen_ai.usage.output_tokens":200,"gen_ai.usage.cache_read.input_tokens":5000,"ygg.usage.turns":3,"ygg.usage.cost_usd":0.25}'
      echo '{"seq":2,"event":"node_failed","ygg.node.id":"build","gen_ai.usage.input_tokens":500,"gen_ai.usage.output_tokens":100,"ygg.usage.turns":2,"ygg.usage.cost_usd":0.125,"ygg.usage.cost_estimated":true}'
      echo '{"seq":3,"event":"grade_finished","ygg.grade.reward":'"$reward"'}'
      echo '{"seq":4,"event":"run_finished","gen_ai.usage.input_tokens":1500,"gen_ai.usage.output_tokens":300,"ygg.usage.turns":5,"ygg.usage.cost_usd":0.375}'
    } >"$proj/.factory/runs/$id/ledger.jsonl"
    echo "Run $id is done."
    exit "${FAKE_RUN_RC:-0}" ;;
  grade)
    id="$(ls -1 "$proj/.factory/runs" | tail -n 1)"
    echo '{"seq":9,"event":"grade_finished"}' >>"$proj/.factory/runs/$id/ledger.jsonl"
    echo "Graded run $id: smoke-notes 1.0.0 against suite v1." ;;
esac
EOF
# The fake podman: no container, or the containers a test asks for. A container line is
# "<name> <grader label or -> <mount source>": the agents of each case, and the grader that holds the suite.
cat >"$T/bin/podman" <<'EOF'
#!/usr/bin/env bash
w="$(ls -d "$FAKE_IT"/smoke-*/ 2>/dev/null | tail -n 1)"; w="${w%/}"
case "$1" in
  ps)
    case "$*" in *label=ygg.grader*) [ -z "${FAKE_LEFTOVER:-}" ] || echo abc123 ;; *) [ -z "$w" ] || echo agent1 ;; esac ;;
  inspect)
    [ -z "$w" ] || {
      echo "ygg_reference_work_1 - $w/reference/project/repos/notes"
      echo "ygg_empty_work_1 - $w/empty/project/repos/notes"
      echo "ygg-grader-run-smoke-notes $FAKE_RUN $w/suites/smoke-notes/v1/tests"
      [ -z "${FAKE_SUITE_LEAK:-}" ] || echo "ygg_leaky_work_1 - $w/suites/smoke-notes"
    } ;;
esac
EOF
printf '#!/usr/bin/env bash\necho 0.89.0\n' >"$T/bin/devcontainer"
chmod +x "$T/bin/ygg" "$T/bin/podman" "$T/bin/devcontainer"
export PATH="$T/bin:$PATH" FAKE_IT="$T/it" FAKE_RUN=run1
# YGG_CMD is how ygg runs; this wrapper gives the fake its verb.
cat >"$T/bin/ygg-cmd" <<'EOF'
#!/usr/bin/env bash
verb="$1"; [ "$verb" != sandbox ] || verb=build
FAKE_VERB="$verb" exec "$(dirname "$0")/ygg" "$@"
EOF
chmod +x "$T/bin/ygg-cmd"
export YGG_CMD="$T/bin/ygg-cmd" YGG_BIND="$T/bind" YGG_ODIN="$T/odin"
mkdir -p "$T/bind"
D="$T/it"
newest() { find "$D" -maxdepth 1 -type d -name "$1" | sort | tail -n 1; } # the newest folder the script made
gargs=(--folder "$D" --tasks "$M" --odin "$T/odin")

# --- ygg-cost.sh.
L="$T/ledger.jsonl"
{
  echo '{"seq":1,"event":"node_started"}'
  echo '{"seq":2,"event":"node_finished","gen_ai.usage.input_tokens":1000,"gen_ai.usage.output_tokens":200,"gen_ai.usage.cache_read.input_tokens":5000,"ygg.usage.turns":3,"ygg.usage.cost_usd":0.25}'
  echo '{"seq":3,"event":"node_failed","gen_ai.usage.input_tokens":500,"gen_ai.usage.output_tokens":100,"ygg.usage.turns":2,"ygg.usage.cost_usd":0.125,"ygg.usage.cost_estimated":true}'
  echo '{"seq":4,"event":"run_finished","gen_ai.usage.input_tokens":1500,"gen_ai.usage.output_tokens":300,"ygg.usage.turns":5,"ygg.usage.cost_usd":0.375}'
  echo 'not json'
} >"$L"
printf 'budget:\n  per_run: { tokens: 400000, turns: 100, usd: 3 }\n' >"$T/cap.yaml"
run "$S/ygg-cost.sh" "$L" "$T/cap.yaml"
check "the cost counts the two sessions and not the run's own total" has "2 session line(s): 1500 tokens in, 300 out, 5000 cache read, 5 turns"
check "the cost is the sum of the sessions" has 'cost $0.3750'
check "an estimated cost is marked" has "an estimate"
check "the per_run cap is printed beside it" has 'per_run cap is $3'
run "$S/ygg-cost.sh" "$T/nope.jsonl"
check "a missing ledger is refused" test "$rc" -eq 2

# --- ygg-smoke-grade.sh.
run "$S/ygg-smoke-grade.sh" --nope
check "an unknown flag is refused" test "$rc" -eq 2
run "$S/ygg-smoke-grade.sh" "${gargs[@]}"
check "a missing factory.yaml is refused" test "$rc" -eq 2
printf 'sandbox:\n  engine: unix:///run/ygg-test.sock\n' >"$D/factory.yaml"
run "$S/ygg-smoke-grade.sh" --folder "$D" --tasks "$T/nowhere" --odin "$T/odin"
check "a missing task folder is refused" test "$rc" -eq 2
run "$S/ygg-smoke-grade.sh" "${gargs[@]}"
check "a good run passes every check and exits 0" test "$rc" -eq 0
check "the reference case grades 1" has "smoke-grade: reference reward 1"
check "the empty case grades 0" has "smoke-grade: empty reward 0"
check "no check failed" hasnt "FAIL"
check "the watch sees the grader hold the suite folder" has "the watch saw the grader container hold the suite folder"
w="$(newest "smoke-grade-*" | head -n 1)"
check "the suite folder is a copy of the PUBLIC suite and nothing else" diff -r "$M/smoke-notes/sample-suite/tests" "$w/suites/smoke-notes/v1/tests"
check "the suite is named by the task's metadata.suite" test -f "$w/suites/smoke-notes/v1/tests/manifest.json"
check "the reference answers write the reference files" grep -q 'path: "server.js"' "$w/reference/script.yaml"
check "and make start.sh executable" grep -q '"chmod", "+x", "start.sh"' "$w/reference/script.yaml"
check "the empty answers write no reference file" test -z "$(grep 'server.js' "$w/empty/script.yaml")"
check "a content with quotes and tabs is written as one YAML string" grep -q 'a \\\\\\"quote' "$w/reference/script.yaml"
check "the project holds the start.sh that runs the leaf's" grep -q 'repos/notes' "$w/reference/project/start.sh"
check "the grader runs with no limit on an engine that has none" grep -q 'memory: none' "$w/reference/factory.yaml"
check "the folder of the suite is outside both projects" test -z "$(find "$w/reference/project" "$w/empty/project" -path '*suites*' -not -path '*/.git/*' | head -n 1)"
sleep 1
run "$S/ygg-smoke-grade.sh" "${gargs[@]}" --limits
check "--limits asks for 4g and 4 CPUs" grep -q 'memory: 4g' "$(newest "smoke-grade-*")/reference/factory.yaml"
sleep 1
FAKE_LEAK=1 run "$S/ygg-smoke-grade.sh" "${gargs[@]}"
check "a score.json outside the run folder fails the smoke" test "$rc" -eq 1
check "and the failing line says which check" has "FAIL  reference: score.json is in the run folder and nowhere else"
sleep 1
FAKE_REWARD=0.5 run "$S/ygg-smoke-grade.sh" "${gargs[@]}"
check "a reference that does not grade 1 fails the smoke" has "FAIL  reference: reward is 1"
sleep 1
FAKE_REWARD=1 run "$S/ygg-smoke-grade.sh" "${gargs[@]}"
check "an empty product that grades 1 fails the smoke" has "FAIL  empty: reward is below 1"
sleep 1
FAKE_LEFTOVER=1 run "$S/ygg-smoke-grade.sh" "${gargs[@]}"
check "a grader container left behind fails the smoke" has "FAIL  reference: no container with the label ygg.grader is left"
sleep 1
FAKE_SUITE_LEAK=1 run "$S/ygg-smoke-grade.sh" "${gargs[@]}"
check "an agent container that holds the suite folder fails the smoke" has "FAIL  reference: the watch saw"
check "and the smoke exits 1" test "$rc" -eq 1
sleep 1
FAKE_DOCTOR_RC=1 run "$S/ygg-smoke-grade.sh" "${gargs[@]}"
check "a doctor that does not find 0 grader containers fails the smoke" has "FAIL  reference: ygg doctor finds 0 grader containers"

# --- ygg-smoke-real.sh. The credentials are made-up values; none may appear anywhere in the output.
MARK_A='sekret-claude-0123456789'
MARK_B='sekret-openrouter-9876543210'
rargs=(--folder "$D" --tasks "$M" --odin "$T/odin" --env "$T/factory.env")
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --dry-run
check "a missing credentials file is refused" test "$rc" -eq 2
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$MARK_A" >"$T/factory.env"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --dry-run
check "a credentials file with one name missing is refused" test "$rc" -eq 2
check "and the refusal names the missing variable" has "OPENROUTER_API_KEY"
check "and prints no value" hasnt "$MARK_A"
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\nOPENROUTER_API_KEY=\n' "$MARK_A" >"$T/factory.env"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --dry-run
check "a name with no value is refused" test "$rc" -eq 2
printf 'export CLAUDE_CODE_OAUTH_TOKEN=%s\nOPENROUTER_API_KEY=%s\n' "$MARK_A" "$MARK_B" >"$T/factory.env"
rm -f "$T/args.log"
sleep 1
FAKE_ARGS_LOG="$T/args.log" run "$S/ygg-smoke-real.sh" "${rargs[@]}" --dry-run
check "a dry run exits 0" test "$rc" -eq 0
check "a dry run says what it would run, under a wall clock" has "would run: timeout --signal=INT --kill-after=2m 90m"
check "a dry run runs the doctor" grep -q '^doctor ' "$T/args.log"
check "a dry run does not start the run" test -z "$(grep '^run ' "$T/args.log")"
check "a dry run does not load the credentials" test -z "$(grep 'credentials were loaded' "$T/args.log")"
check "a dry run prints the caps" has "per_run: { tokens: 400000, turns: 100, usd: 3 }"
rc_yaml="$(newest "smoke-real-*")/factory.yaml"
check "the config has no place left to fill" test -z "$(grep -h '@[A-Z]*@' "$rc_yaml")"
check "the config has the real agents" grep -q 'agent: claude-code' "$rc_yaml"
check "and the reviewer on OpenRouter" grep -q 'agent: opencode' "$rc_yaml"
check "and dollar caps for the day" grep -q 'per_day:.*usd: 6' "$rc_yaml"
sleep 1
FAKE_DOCTOR_RC=1 FAKE_ARGS_LOG="$T/args2.log" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "a config that doctor refuses stops the script before the run" test "$rc" -eq 2
check "and the run did not start" test -z "$(grep '^run ' "$T/args2.log")"
sleep 1
FAKE_ARGS_LOG="$T/args3.log" run "$S/ygg-smoke-real.sh" "${rargs[@]}" --build
check "a run with the fake ygg exits with the run's code" test "$rc" -eq 0
check "the images are built on request" has "built"
check "the credentials were loaded for the run" grep -q 'credentials were loaded' "$T/args3.log"
check "no credential value is printed" hasnt "$MARK_A"
check "nor the second" hasnt "$MARK_B"
check "the score is printed" has "reward 0, fail-to-pass 6/6"
check "the cost is printed from the ledger" has 'cost $0.3750'
check "and the cap beside it" has 'per_run cap is $3'
w="$(newest "smoke-real-*")"
check "no credential value is in the saved report or run output" test -z "$(grep -rl -e "$MARK_A" -e "$MARK_B" "$w" 2>/dev/null | head -n 1)"
sleep 1
FAKE_RUN_SLEEP=30 run "$S/ygg-smoke-real.sh" "${rargs[@]}" --wall 1s
check "the wall clock ends a run that hangs, and the code is 124" test "$rc" -eq 124
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --wall soon
check "a wall clock that is not a duration is refused" test "$rc" -eq 2
# The script does not read the credentials file: every line that names it is on this list.
bad="$(grep -n 'envfile' "$S/ygg-smoke-real.sh" | grep -v -E 'envfile=|--env\)|\[ -f "\$envfile" \]|grep -c -E "[^"]*" "\$envfile"|\. "\$envfile"|\$envfile (has|is missing)|source=|FILE' || true)"
check "the only uses of the credentials file are the existence test, grep -c on a name, and the subshell load" test -z "$bad"
check "the credentials file is not read by cat, head, tail, sed or awk" test -z "$(grep -E '(cat|head|tail|sed|awk|cut) [^|]*envfile' "$S/ygg-smoke-real.sh")"

exit "$fail"

#!/usr/bin/env bash
# Set up a proof run (v0-T290): the `software` graph on the real client-gallery-lite, with the realms, three roles
# the operator names and caps the operator sets. Every proof run is set up the same way, so that `ygg metrics
# --compare` compares two factories and not two setups. IT WILL COST MONEY when the run exists (v0-T291 adds it):
# this part makes the project and the config and stops; --dry-run is the only way to finish today.
#   ygg-proof-run.sh --name NAME [--mode key-points|unattended|step-by-step] [--planner AGENT:MODEL]
#                    [--implementer AGENT:MODEL] [--reviewer AGENT:MODEL] [--run-turns N] [--run-tokens N]
#                    [--run-usd N] [--day-turns N] [--day-tokens N] [--day-usd N] [--baseline RUN_ID] [--dry-run]
#                    [--build] [--folder DIR] [--env FILE] [--tasks DIR] [--suites DIR] [--yggdrasil DIR]
#                    [--wall TIME] [--clip]
# AGENT is claude-code or opencode; an opencode MODEL is openrouter/<model>; a MODEL has only A-Za-z0-9._/:-
# because it goes into a YAML line. Defaults: key-points; planner and implementer claude-code:sonnet; reviewer
# opencode:openrouter/qwen/qwen3.8-27b; a run 1,500 turns, 12,000,000 tokens, $5; a day 2,000 turns, 24,000,000
# tokens, $10; --wall 8h; DIR $HOME/ygg-it; FILE $HOME/.config/ouroboric/factory.env; --tasks ../mimir;
# --suites $HOME/ygg-it/hidden-suites; --yggdrasil the umbrella beside this repo. The task is client-gallery-lite
# (YGG_PROOF_TASK names another, for tests); its suite is the `suite` key of its task.toml.
# In order, it
#   1. checks the flags (exit 2 on the first bad one), the engine (ygg-engine.sh; YGG_ENGINE_CHECK=0 skips it)
#      and the tools (git, python3, timeout, sha256sum);
#   2. checks the task: task.toml and instruction.md, and that the SHA-256 of instruction.md is the brief_sha256
#      of task.toml. A changed brief is another task: a proof run uses the frozen one;
#   3. checks the suites folder with `test -d SUITES/TASK/SUITE` and nothing more: it is never listed, read or
#      searched, and neither it nor the tasks folder is inside the other or inside the project;
#   4. checks the credentials file WITHOUT reading it, for the adapters the roles name only: claude-code needs
#      CLAUDE_CODE_OAUTH_TOKEN, opencode needs OPENROUTER_API_KEY, each on one line with a value after the equals
#      sign (grep -c counts the lines; no value is printed or kept);
#   5. makes DIR/proof-NAME-TIME/project (a git repository, umbrella.yaml with root: true) and
#      DIR/proof-NAME-TIME/factory.yaml, filled from scripts/testdata/proof/factory.proof.example.yaml (a "usd"
#      line only when a role is an opencode role, which pays per token);
#   6. runs `ygg doctor` on that config and prints the plan: what would run.
# --dry-run stops there with exit 0. Without it the script stops with exit 2 until v0-T291 adds the run.
# For tests and other machines: YGG_CMD (how ygg runs), YGG_BIND (the bind mount, default /mnt/wsl/ygg-bind).
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { echo "usage: ygg-proof-run.sh --name NAME [--mode MODE] [--planner|--implementer|--reviewer AGENT:MODEL] [--run-turns|--run-tokens|--run-usd|--day-turns|--day-tokens|--day-usd N] [--baseline RUN_ID] [--dry-run] [--build] [--folder DIR] [--env FILE] [--tasks DIR] [--suites DIR] [--yggdrasil DIR] [--wall TIME] [--clip]" >&2; exit 2; }
fail() { echo "proof-run: $*" >&2; exit 2; }
name="" mode=key-points dry=0 build=0 clip=0 baseline="" wall=8h
planner=claude-code:sonnet implementer=claude-code:sonnet reviewer=opencode:openrouter/qwen/qwen3.8-27b
run_turns=1500 run_tokens=12000000 run_usd=5 day_turns=2000 day_tokens=24000000 day_usd=10
dir="$HOME/ygg-it" envfile="$HOME/.config/ouroboric/factory.env" tasks="$HERE/../../mimir"
suites="$HOME/ygg-it/hidden-suites" ygg_dir="$HERE/../../yggdrasil"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --build) build=1; shift ;;
    --clip) clip=1; shift ;;
    --name) [ $# -ge 2 ] || usage; name="$2"; shift 2 ;;
    --mode) [ $# -ge 2 ] || usage; mode="$2"; shift 2 ;;
    --planner) [ $# -ge 2 ] || usage; planner="$2"; shift 2 ;;
    --implementer) [ $# -ge 2 ] || usage; implementer="$2"; shift 2 ;;
    --reviewer) [ $# -ge 2 ] || usage; reviewer="$2"; shift 2 ;;
    --run-turns) [ $# -ge 2 ] || usage; run_turns="$2"; shift 2 ;;
    --run-tokens) [ $# -ge 2 ] || usage; run_tokens="$2"; shift 2 ;;
    --run-usd) [ $# -ge 2 ] || usage; run_usd="$2"; shift 2 ;;
    --day-turns) [ $# -ge 2 ] || usage; day_turns="$2"; shift 2 ;;
    --day-tokens) [ $# -ge 2 ] || usage; day_tokens="$2"; shift 2 ;;
    --day-usd) [ $# -ge 2 ] || usage; day_usd="$2"; shift 2 ;;
    --baseline) [ $# -ge 2 ] || usage; baseline="$2"; shift 2 ;;
    --folder) [ $# -ge 2 ] || usage; dir="$2"; shift 2 ;;
    --env) [ $# -ge 2 ] || usage; envfile="$2"; shift 2 ;;
    --tasks) [ $# -ge 2 ] || usage; tasks="$2"; shift 2 ;;
    --suites) [ $# -ge 2 ] || usage; suites="$2"; shift 2 ;;
    --yggdrasil) [ $# -ge 2 ] || usage; ygg_dir="$2"; shift 2 ;;
    --wall) [ $# -ge 2 ] || usage; wall="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# 1. The flags.
[ -n "$name" ] || fail "--name is needed: the run's name, such as baseline-1"
[[ $name =~ ^[a-z0-9-]+$ ]] || fail "--name '$name' has characters outside a-z0-9-"
case "$mode" in key-points | unattended | step-by-step) ;; *) fail "--mode is key-points, unattended or step-by-step, not '$mode'" ;; esac
[[ $wall =~ ^[1-9][0-9]*[smh]$ ]] || fail "--wall is a number and s, m or h, such as 8h"
for pair in run-turns:"$run_turns" run-tokens:"$run_tokens" day-turns:"$day_turns" day-tokens:"$day_tokens"; do
  [[ ${pair#*:} =~ ^[1-9][0-9]*$ ]] || fail "--${pair%%:*} is a whole number above 0, not '${pair#*:}'"
done
for pair in run-usd:"$run_usd" day-usd:"$day_usd"; do
  [[ ${pair#*:} =~ ^[0-9]+(\.[0-9]+)?$ ]] || fail "--${pair%%:*} is a number of dollars such as 5 or 2.5, not '${pair#*:}'"
done
if [ -n "$baseline" ]; then [[ $baseline =~ ^[A-Za-z0-9._-]+$ ]] || fail "--baseline '$baseline' is not a run id"; fi
# A role goes into a YAML line as it is, so its model has only the characters a model id needs.
role_ok() { # FLAG VALUE: sets agent_of and model_of
  local flag="$1" v="$2" agent model
  [[ $v == *:* ]] || fail "$flag is AGENT:MODEL, with AGENT claude-code or opencode, such as claude-code:sonnet"
  agent="${v%%:*}" model="${v#*:}"
  [[ $model =~ ^[A-Za-z0-9._/:-]+$ ]] || fail "$flag has a MODEL with characters outside A-Za-z0-9._/:-"
  case "$agent" in
    claude-code) ;;
    opencode) [[ $model == openrouter/?* ]] || fail "$flag: an opencode MODEL is openrouter/<model>, such as opencode:openrouter/qwen/qwen3.8-27b" ;;
    *) fail "$flag is AGENT:MODEL, with AGENT claude-code or opencode, not '$agent'" ;;
  esac
}
role_ok --planner "$planner"; role_ok --implementer "$implementer"; role_ok --reviewer "$reviewer"
paid=0 need_claude=0 need_router=0
for r in "$planner" "$implementer" "$reviewer"; do
  case "${r%%:*}" in claude-code) need_claude=1 ;; opencode) need_router=1; paid=1 ;; esac
done

# The engine, the tools.
export PATH="$dir/dc/node_modules/.bin:$PATH"
if [ "${YGG_ENGINE_CHECK:-1}" = 1 ]; then
  engine_env="$("$HERE/ygg-engine.sh" env --folder "$dir")" || exit 2
  eval "$engine_env"
fi
[ -f "$dir/factory.yaml" ] || fail "$dir/factory.yaml is missing; it names the engine (sandbox.engine)"
engine="$(sed -n 's/^[[:space:]]*engine:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$dir/factory.yaml" | head -n 1)"
case "$engine" in unix://*) ;; *) fail "sandbox.engine in $dir/factory.yaml is '${engine:-missing}'; it must be a unix:// URL" ;; esac
for tool in git python3 timeout sha256sum; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"; done
ygg="${YGG_CMD:-ygg}"
command -v -- "${ygg%% *}" >/dev/null 2>&1 || fail "no ygg on the path (YGG_CMD names how it runs)"

# 2. The task, and that its brief is the frozen one.
task="${YGG_PROOF_TASK:-client-gallery-lite}"
tasks="$(cd "$tasks" 2>/dev/null && pwd)" || fail "no task folder at $tasks (--tasks)"
ygg_dir="$(cd "$ygg_dir" 2>/dev/null && pwd)" || fail "no yggdrasil folder at $ygg_dir (--yggdrasil)"
for f in "$tasks/$task/task.toml" "$tasks/$task/instruction.md"; do [ -f "$f" ] || fail "no task: $f is missing"; done
suite="$(sed -n 's/^suite[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$tasks/$task/task.toml" | head -n 1)"
[ -n "$suite" ] || fail "$tasks/$task/task.toml has no suite key"
[[ $suite =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "the suite '$suite' of $task is not a suite version"
frozen="$(sed -n 's/^brief_sha256[[:space:]]*=[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$tasks/$task/task.toml" | head -n 1)"
have="$(sha256sum "$tasks/$task/instruction.md" | cut -d' ' -f1)"
[ -n "$frozen" ] && [ "$have" = "$frozen" ] || fail "$tasks/$task/instruction.md is not the frozen brief: its SHA-256 is $have and task.toml says '${frozen:-nothing}'; a changed brief is another task"

# 3. The suites folder: one test -d, never listed or read.
suites="$(cd "$suites" 2>/dev/null && pwd)" || fail "no suites folder at $suites for $task/$suite (--suites)"
test -d "$suites/$task/$suite" || fail "the suites folder $suites has no $task/$suite (--suites)"
work="$dir/proof-$name-$(date +%Y%m%d-%H%M%S)"
dir_abs="$(cd "$dir" && pwd)"
work="$dir_abs/${work##*/}"
inside() { case "$1/" in "$2"/*) return 0 ;; esac; return 1; } # inside A B: A is B or below B
if inside "$suites" "$tasks"; then fail "the suites folder $suites is inside the tasks folder $tasks"; fi
if inside "$tasks" "$suites"; then fail "the tasks folder $tasks is inside the suites folder $suites"; fi
for f in "$tasks" "$suites"; do
  if inside "$f" "$work"; then fail "$f is inside the project folder $work"; fi
done

# 4. The credentials, by name. grep -c prints a count and nothing else; no line is shown, stored or compared.
[ -f "$envfile" ] || fail "the credentials file $envfile is missing"
names=()
[ "$need_claude" -eq 0 ] || names+=(CLAUDE_CODE_OAUTH_TOKEN)
[ "$need_router" -eq 0 ] || names+=(OPENROUTER_API_KEY)
for n_ in "${names[@]}"; do
  n="$(grep -c -E "^(export[[:space:]]+)?${n_}=[^[:space:]]" "$envfile" || true)"
  [ "$n" = 1 ] || fail "$envfile has $n line(s) that set $n_ with a value; the roles need exactly 1"
done

# 5. The project and the config.
project="$work/project"
mkdir -p "$project"
git -C "$project" init -q -b main
printf 'root: true\nowner: ouroboric-dev\nvisibility: private\n' >"$project/umbrella.yaml"
git -C "$project" add umbrella.yaml
git -C "$project" -c user.name=ygg -c user.email=ygg@example.invalid commit -q -m "the proof run project"
example="$HERE/testdata/proof/factory.proof.example.yaml"
[ -f "$example" ] || fail "$example is missing"
usd_run="" usd_day=""
if [ "$paid" -eq 1 ]; then usd_run=", usd: $run_usd" usd_day=", usd: $day_usd"; fi
text="$(<"$example")"
fill() { text="${text//@$1@/$2}"; }
fill MODE "$mode"
fill PLANNER_AGENT "${planner%%:*}"; fill PLANNER_MODEL "${planner#*:}"
fill IMPLEMENTER_AGENT "${implementer%%:*}"; fill IMPLEMENTER_MODEL "${implementer#*:}"
fill REVIEWER_AGENT "${reviewer%%:*}"; fill REVIEWER_MODEL "${reviewer#*:}"
fill RUN_TOKENS "$run_tokens"; fill RUN_TURNS "$run_turns"; fill RUN_USD "$usd_run"
fill DAY_TOKENS "$day_tokens"; fill DAY_TURNS "$day_turns"; fill DAY_USD "$usd_day"
fill ENGINE "$engine"; fill FOLDER "$dir_abs"; fill BIND "${YGG_BIND:-/mnt/wsl/ygg-bind}"
fill REALMS "$ygg_dir"; fill GRAPHS "$ygg_dir/voluspa"
fill TASKS "$tasks"; fill SUITES "$suites"
printf '%s\n' "$text" >"$work/factory.yaml"
if grep -q '@[A-Z_]*@' "$work/factory.yaml"; then fail "$work/factory.yaml still has a place to fill: $(grep -o '@[A-Z_]*@' "$work/factory.yaml" | sort -u | tr '\n' ' ')"; fi
echo "proof-run: made $work"
echo "proof-run: the task is $task, suite $suite; the brief is the frozen one (SHA-256 $have)"
[ "$paid" -eq 1 ] || echo "proof-run: no role is paid per token, so the config has no usd line"

# 6. doctor, and the plan.
echo "proof-run: ygg doctor on that config"
if ! eval "$ygg doctor --project '$project' --config '$work/factory.yaml'"; then fail "ygg doctor refused the config; nothing was spent"; fi
run="$ygg run --project '$project' --config '$work/factory.yaml' --graph software --brief '$tasks/$task/instruction.md'"
echo "proof-run: the plan: mode $mode; planner $planner, implementer $implementer, reviewer $reviewer"
echo "proof-run: the caps in $work/factory.yaml:"
{ grep -E '^  per_(run|day):' "$work/factory.yaml" || true; } | sed 's/^/  /'
[ -z "$baseline" ] || echo "proof-run: after the run: compare with the baseline run $baseline"
[ "$clip" -eq 0 ] || echo "proof-run: after the run: the report is copied to the clipboard"
if [ "$dry" -eq 1 ]; then
  [ "$build" -eq 0 ] || echo "proof-run: would run: $ygg sandbox build --config '$work/factory.yaml' --realm '$ygg_dir'"
  echo "proof-run: would run: timeout --signal=INT --kill-after=2m $wall $run"
  echo "proof-run: dry run: nothing was started and the credentials were not loaded"
  exit 0
fi
fail "the run itself is not in this script yet (v0-T291); use --dry-run. The project is $project"

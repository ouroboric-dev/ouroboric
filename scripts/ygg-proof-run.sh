#!/usr/bin/env bash
# Set up a proof run (v0-T290): the `software` graph on the real client-gallery-lite, with the realms, three roles
# the operator names and caps the operator sets. Every proof run is set up the same way, so that `ygg metrics
# --compare` compares two factories and not two setups. IT WILL COST MONEY (without --dry-run):
# the script makes the project and the config, runs the factory, grades the run and prints the evidence.
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
# --dry-run stops there with exit 0. Without it (v0-T291) the script then
#   7. with --build runs `ygg sandbox build --all --config C`; runs `ygg run --project P --config C --graph software
#      --brief <task>/instruction.md --mode M` under `timeout --signal=INT --kill-after=2m WALL`, with the credentials
#      loaded in that subshell only (never exported by this shell, never in an argument), its output (credential
#      values removed) shown as it comes and kept in DIR/proof-NAME-TIME/run.txt;
#   8. prints the exit code (0 done, 1 a node failed, 3 stopped, 4 paused, 5 done with tasks given up, 124 the wall
#      clock) and, after a run that ended 0 or 5, runs `ygg grade RUN`; after any ending runs `ygg metrics RUN`
#      (with --baseline RUN_ID also `ygg metrics --compare RUN_ID RUN`, printed as the CLI gives it: this script
#      judges nothing), `ygg report RUN`, ygg-cost.sh on the ledger and ygg-evidence.sh. Everything goes through a
#      filter that replaces the credentials' exact values, and is kept in DIR/proof-NAME-TIME/report.txt (--clip
#      copies it to the Windows clipboard);
#   9. for a run that stopped (3) or paused (4), ends with the command that continues it (`ygg approve`, run under
#      ygg-engine.sh, or `ygg resume`). A stopped or paused run is not graded. The exit code is the run's.
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
# Folders go into factory.yaml as they are, so their characters cannot change how a YAML line parses.
safe_path() { # FLAG VALUE
  [[ $2 =~ ^[A-Za-z0-9._/@+-]+$ ]] || fail "$1 '$2' has a character outside A-Za-z0-9._/@+- (no spaces); it goes into factory.yaml"
}
safe_path --folder "$dir"; safe_path --tasks "$tasks"; safe_path --suites "$suites"; safe_path --yggdrasil "$ygg_dir"
safe_path YGG_BIND "${YGG_BIND:-/mnt/wsl/ygg-bind}"
# A role goes into a YAML line as it is, so its model has only the characters a model id needs.
role_ok() { # FLAG VALUE: sets agent_of and model_of
  local flag="$1" v="$2" agent model
  [[ $v == *:* ]] || fail "$flag is AGENT:MODEL, with AGENT claude-code or opencode, such as claude-code:sonnet"
  agent="${v%%:*}" model="${v#*:}"
  [[ $model =~ ^[A-Za-z0-9._/:-]+$ && $model != *: ]] || fail "$flag has a MODEL with characters outside A-Za-z0-9._/:- or ends in a colon"
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
safe_path sandbox.engine "${engine#unix://}"
for tool in git python3 timeout sha256sum; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"; done
ygg="${YGG_CMD:-ygg}"
read -r -a ygg_arr <<<"$ygg"
command -v -- "${ygg_arr[0]:-ygg}" >/dev/null 2>&1 || fail "no ygg on the path (YGG_CMD names how it runs)"

# 2. The task, and that its brief is the frozen one.
task="${YGG_PROOF_TASK:-client-gallery-lite}"
tasks="$(cd -P -- "$tasks" 2>/dev/null && pwd -P)" || fail "no task folder at $tasks (--tasks)"
ygg_dir="$(cd -P -- "$ygg_dir" 2>/dev/null && pwd -P)" || fail "no yggdrasil folder at $ygg_dir (--yggdrasil)"
for f in "$tasks/$task/task.toml" "$tasks/$task/instruction.md"; do [ -f "$f" ] || fail "no task: $f is missing"; done
suite="$(sed -n 's/^suite[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$tasks/$task/task.toml" | head -n 1)"
[ -n "$suite" ] || fail "$tasks/$task/task.toml has no suite key"
[[ $suite =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "the suite '$suite' of $task is not a suite version"
frozen="$(sed -n 's/^brief_sha256[[:space:]]*=[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$tasks/$task/task.toml" | head -n 1)"
have="$(sha256sum "$tasks/$task/instruction.md" | cut -d' ' -f1)"
[ -n "$frozen" ] && [ "$have" = "$frozen" ] || fail "$tasks/$task/instruction.md is not the frozen brief: its SHA-256 is $have and task.toml says '${frozen:-nothing}'; a changed brief is another task"

# 3. The suites folder: one test -d, never listed or read.
# readlink -f resolves the links of the path without entering or listing the suites folder.
suites_raw="$suites"
suites="$(readlink -f -- "$suites" 2>/dev/null)" && [ -n "$suites" ] || fail "no suites folder at $suites_raw for $task/$suite (--suites)"
test -d "$suites/$task/$suite" || fail "the suites folder $suites has no $task/$suite (--suites)"
work="$dir/proof-$name-$(date +%Y%m%d-%H%M%S)"
dir_abs="$(cd -P -- "$dir" && pwd -P)"
work="$dir_abs/${work##*/}"
for pair in tasks:"$tasks" suites:"$suites" yggdrasil:"$ygg_dir" folder:"$dir_abs"; do safe_path "--${pair%%:*} (resolved)" "${pair#*:}"; done
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
if ! "${ygg_arr[@]}" doctor --project "$project" --config "$work/factory.yaml"; then fail "ygg doctor refused the config; nothing was spent"; fi
# Commands are printed with %q and never run through eval.
q() { printf '%q ' "$@"; }
run_argv=("${ygg_arr[@]}" run --project "$project" --config "$work/factory.yaml" --graph software --brief "$tasks/$task/instruction.md" --mode "$mode")
build_argv=("${ygg_arr[@]}" sandbox build --all --config "$work/factory.yaml")
run_cmd="$(q "${run_argv[@]}")"
build_cmd="$(q "${build_argv[@]}")"
echo "proof-run: the plan: mode $mode; planner $planner, implementer $implementer, reviewer $reviewer"
echo "proof-run: the caps in $work/factory.yaml:"
{ grep -E '^  per_(run|day):' "$work/factory.yaml" || true; } | sed 's/^/  /'
[ -z "$baseline" ] || echo "proof-run: after the run: compare with the baseline run $baseline"
[ "$clip" -eq 0 ] || echo "proof-run: after the run: the report is copied to the clipboard"
if [ "$dry" -eq 1 ]; then
  [ "$build" -eq 0 ] || echo "proof-run: would run: $build_cmd"
  echo "proof-run: would run: timeout --signal=INT --kill-after=2m $wall $run_cmd"
  echo "proof-run: dry run: nothing was started and the credentials were not loaded"
  exit 0
fi

# 7. The run. Only `ygg run` starts model sessions, so only it (and the output filter, which needs the exact values
# to remove them) gets the credentials: each is sourced in its own subshell and nothing is exported by this shell.
umask 077 # run.txt and report.txt are private to this user
load_env() { # in a subshell only
  { set +x; } 2>/dev/null # no trace of the sourced assignments, even under bash -x or SHELLOPTS=xtrace
  set -a
  # shellcheck source=/dev/null
  . "$envfile"
  set +a
}
# The filter works on bytes (any byte survives), replaces the exact values, and if it cannot run it drains its input
# so the writer is never killed by SIGPIPE: the output is then withheld, not shown unfiltered.
redact() {
  (
    load_env
    python3 -I -u -c '
import os, re, sys
name = re.compile(rb"TOKEN|KEY|SECRET|PASSWORD|CREDENTIAL", re.I)
vals = sorted({v for k, v in os.environb.items() if name.search(k) and len(v) >= 8}, key=len, reverse=True)
out = sys.stdout.buffer
for line in sys.stdin.buffer:
    for v in vals:
        line = line.replace(v, b"[REDACTED]")
    out.write(line)
    out.flush()
' || { echo "proof-run: the output filter failed; the output is withheld" >&2; cat >/dev/null; }
  )
}
# The run alone has the credentials. timeout --foreground keeps timeout in this script's process group, so a
# terminal Ctrl-C reaches it and ygg; timeout runs in the background of its subshell and its pid is kept, so that a
# TERM or INT sent to this script (which bash would only handle after the pipeline) is passed on to it. On the wall
# clock timeout sends INT to ygg and, after the grace period, KILL (exit 137).
run_part() {
  if [ "$build" -eq 1 ]; then "${build_argv[@]}" || { echo 2 >"$work/run.rc"; return 0; }; fi
  (
    load_env
    timeout --foreground --signal=INT --kill-after=2m "$wall" "${run_argv[@]}" &
    tp=$!
    echo "$tp" >"$work/run.pid"
    wait "$tp"
    echo "$?" >"$work/run.rc"
  )
}
out="$work/run.txt"
echo "proof-run: starting the run (wall clock $wall); this costs money"
set +e
rm -f "$work/run.pid" "$work/run.rc"
# shellcheck disable=SC2329 # called by the traps
on_signal() { # SIGNAL: pass it to timeout (and so to ygg)
  local p
  p="$(cat "$work/run.pid" 2>/dev/null)" || return 0
  [ -z "$p" ] || kill -s "$1" "$p" 2>/dev/null
  return 0
}
trap 'on_signal TERM' TERM
trap 'on_signal INT' INT
(run_part 2>&1 | redact | tee "$out") &
pl=$!
while kill -0 "$pl" 2>/dev/null; do wait "$pl"; done
trap - TERM INT
rm -f "$work/run.pid"
set -e
rc="$(cat "$work/run.rc" 2>/dev/null || echo 2)"
[[ $rc =~ ^[0-9]+$ ]] || rc=2
echo "proof-run: the run ended with exit code $rc (0 done, 1 a node failed, 3 stopped, 4 paused, 5 done with tasks given up, 124 the wall clock, 130 or 143 ended by INT or TERM, 137 killed after the grace period, 141 SIGPIPE)"

# 8. The grade and the evidence. The run's id is the newest folder in the project's runs. None of these needs a
# credential; the filter removes the exact values anyway, from anything a tool prints.
id="$(find "$project/.factory/runs" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n 1 || true)"
report="$work/report.txt"
if [ -z "$id" ] || ! [[ $id =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "proof-run: the run left no run folder in $project/.factory/runs; nothing to grade or report" >&2
  echo "proof-run: the folder is $work"
  exit "$rc"
fi
step() { # TITLE CMD...: a heading, then the command's output; its exit code is noted, never fatal
  echo "## $1"; shift
  "$@" || echo "(exited $?)"
  echo
}
evidence_part() {
  echo "# proof run $name: run $id, exit code $rc"
  echo "mode $mode; planner $planner, implementer $implementer, reviewer $reviewer; brief SHA-256 $have"
  echo
  case "$rc" in 0 | 5) step "ygg grade" "${ygg_arr[@]}" grade "$id" --project "$project" ;; esac
  step "ygg metrics" "${ygg_arr[@]}" metrics "$id" --project "$project"
  if [ -n "$baseline" ]; then
    step "ygg metrics --compare $baseline $id" "${ygg_arr[@]}" metrics --compare "$baseline" "$id" --project "$project"
  fi
  step "ygg report" "${ygg_arr[@]}" report "$id" --project "$project"
  if [ -f "$project/.factory/runs/$id/ledger.jsonl" ]; then
    step "cost" "$HERE/ygg-cost.sh" "$project/.factory/runs/$id/ledger.jsonl" "$work/factory.yaml"
    step "evidence" env YGG_CMD="$ygg" "$HERE/ygg-evidence.sh" --output "$out" "$project" "$id"
  fi
}
set +e # nothing after the run may change the run's exit code
evidence_part 2>&1 | redact | tee "$report" || true
if [ "$clip" -eq 1 ]; then
  if command -v clip.exe >/dev/null 2>&1 && [ -f "$report" ]; then clip.exe <"$report"; echo "proof-run: report.txt copied to the clipboard"
  else echo "proof-run: --clip needs clip.exe (WSL); the report is in $report" >&2; fi
fi
echo "proof-run: the folder is $work"

# 9. How to continue a run that stopped or paused. This is the last thing printed.
case "$rc" in
  3)
    gate="$(python3 -I - "$project/.factory/runs/$id/run.json" 2>/dev/null <<'PY' || true
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("pending", ""))
except Exception:
    pass
PY
)"
    [[ $gate =~ ^[A-Za-z0-9._-]+$ ]] || gate="<gate>"
    echo "proof-run: the run stopped at an approval point; to continue it (load the credentials in that shell first), run:"
    echo "  $(q "$HERE/ygg-engine.sh" run --folder "$dir_abs" -- "${ygg_arr[@]}" approve "$id" "$gate" --project "$project")"
    ;;
  4)
    echo "proof-run: the run paused (the provider's quota); once it is back, run:"
    echo "  $(q "$HERE/ygg-engine.sh" run --folder "$dir_abs" -- "${ygg_arr[@]}" resume "$id" --project "$project")"
    ;;
esac
exit "$rc"

#!/usr/bin/env bash
# Set up a proof run (v0-T290): the `software` graph on the real client-gallery-lite, with the realms, the roles the
# operator names (planner, implementer, reviewer, retrospective) and caps the operator sets. Every proof run is set up
# the same way, so that `ygg metrics --compare` compares two factories and not two setups. IT WILL COST MONEY (without
# --dry-run): the script makes the project and the config, runs the factory (the run grades itself, and its retro
# follows) and prints the evidence.
#   ygg-proof-run.sh --name NAME [--mode key-points|unattended|step-by-step] [--planner AGENT:MODEL]
#                    [--implementer AGENT:MODEL] [--reviewer AGENT:MODEL]
#                    [--retro-agent AGENT] [--retro-model MODEL]
#                    [--models FILE] [--reviewer-reasoning low|medium|high|off] [--run-turns N] [--run-tokens N] [--run-usd N]
#                    [--day-turns N] [--day-tokens N] [--day-usd N] [--baseline RUN_ID] [--dry-run] [--build]
#                    [--folder DIR] [--env FILE] [--tasks DIR] [--suites DIR] [--yggdrasil DIR] [--wall TIME] [--clip] [--any-ygg]
#   ygg-proof-run.sh --continue RUN_ID (--approve GATE [--note TEXT | --decisions FILE] |
#                    --reject GATE (--reason TEXT | --decisions FILE) | --resume)
#                    [--baseline RUN_ID] [--dry-run] [--folder DIR] [--env FILE] [--wall TIME] [--clip] [--any-ygg]
# AGENT is claude-code or opencode; an opencode MODEL is openrouter/<model> or local/<name> (a model of the operator's
# model list, served by scripts/ygg-models.sh); a MODEL has only A-Za-z0-9._/:- because it goes into a YAML line. Defaults: key-points; planner and implementer claude-code:sonnet; reviewer
# opencode:openrouter/qwen/qwen3.8-27b with --reviewer-reasoning medium (the reviewer role's reasoning effort: a
# Qwen reviewer at the default high stalled a whole session in the rehearsal; a claude-code agent ignores the
# setting, and the line is written for every agent); the retrospective role claude-code:opus (--retro-agent and
# --retro-model; the role that writes the run's retrospective); a run 1,500 turns, 12,000,000 tokens, $5; a day 2,000
# turns, 24,000,000 tokens, $10; --wall 8h; DIR $HOME/ygg-it; FILE $HOME/.config/ouroboric/factory.env;
# --tasks ../mimir; --suites $HOME/ygg-it/hidden-suites; --yggdrasil the umbrella beside this repo.
# A local role (opencode:local/<name>, for the planner, the implementer, the reviewer or the retrospective) needs
# --models FILE, the model list: the config then has `models: { file: FILE }`. FILE must exist; a relative path is made
# absolute from the caller's folder (the config takes a clean absolute path). A local role without --models is refused
# before anything is made, and so is --models with no local role; so are roles on two different local models (the
# server holds one). A local role sets no `reasoning` (ygg refuses it), so a
# local reviewer gets no reasoning line whatever --reviewer-reasoning says, and the plan says so. Only an
# opencode role on openrouter/... is paid per token: only then does the config have usd lines and the credentials
# file need OPENROUTER_API_KEY (claude-code needs CLAUDE_CODE_OAUTH_TOKEN; a local role needs no credential).
# The task is client-gallery-lite (YGG_PROOF_TASK names another, for tests); its suite is the `suite` key of its
# task.toml.
# In order, it
#   1. checks the flags (exit 2 on the first bad one), the engine (ygg-engine.sh; YGG_ENGINE_CHECK=0 skips it)
#      and the tools (git, python3, timeout, sha256sum);
#   2. checks the task: task.toml and instruction.md, and that the SHA-256 of instruction.md is the brief_sha256
#      of task.toml. A changed brief is another task: a proof run uses the frozen one;
#   3. checks the suites folder with `test -d SUITES/TASK/SUITE` and nothing more: it is never listed, read or
#      searched, and neither it nor the tasks folder is inside the other or inside the project;
#   4. checks the credentials file WITHOUT reading it, for the adapters the roles name only: claude-code needs
#      CLAUDE_CODE_OAUTH_TOKEN, opencode on openrouter needs OPENROUTER_API_KEY, each on one line with a value after the equals
#      sign (grep -c counts the lines; no value is printed or kept);
#   5. makes DIR/proof-NAME-TIME/project (a git repository, umbrella.yaml with root: true) and
#      DIR/proof-NAME-TIME/factory.yaml, filled from scripts/testdata/proof/factory.proof.example.yaml (a "usd"
#      line only when a role is an opencode role on openrouter, which pays per token);
#   6. runs `ygg doctor` on that config and prints the plan: what would run.
# --dry-run stops there with exit 0. Without it (v0-T291) the script then
#   7. with --build runs `ygg sandbox build --all --config C`; runs `ygg run --project P --config C --graph software
#      --brief <task>/instruction.md --mode M` under `timeout --signal=INT --kill-after=2m WALL`, with the credentials
#      loaded in that subshell only (never exported by this shell, never in an argument), its output (credential
#      values removed) shown as it comes and kept in DIR/proof-NAME-TIME/run.txt. A Ctrl-C, a closed terminal (HUP)
#      or a TERM stops the run through timeout, once, and the script waits for it to end; after a hang-up what the
#      script still prints goes to DIR/proof-NAME-TIME/hangup.txt;
#   8. prints the exit code (0 done, 1 a node failed, 3 stopped, 4 paused, 5 done with tasks given up, 124 the wall
#      clock); after an abnormal end (any code but 0, 3, 4 and 5) runs `ygg doctor`, which stops the sandboxes a run
#      left; `ygg grade` is not run here, because the run grades itself; after any ending runs `ygg metrics RUN`, with
#      --baseline RUN_ID also `ygg metrics --compare RUN_ID RUN` (printed as the CLI gives it: this script judges
#      nothing; each proof run has its own project, so the two run folders are linked into DIR/proof-NAME-TIME/compare
#      for it), `ygg report RUN`, after a run that ended 0 or 5 also `ygg record RUN` (it writes record.json and prints
#      its path), ygg-cost.sh on the ledger and ygg-evidence.sh. Everything goes through a filter that replaces the
#      credentials' exact values, and is added to DIR/proof-NAME-TIME/report.txt (--clip copies this report to the
#      Windows clipboard);
#      After a run that ended 0 or 5 the script prints the path of record.json and a line for the operator to fill,
#      `ygg score RUN --score N --well "..." --wrong "..."`. A stop, a pause or a failure prints neither: that run can
#      still go on;
#   9. for a run that stopped (3) or paused (4), ends with this script's command that continues it. A stopped or
#      paused run is not finished, so it has no grade yet. The exit code is the run's.
# --baseline RUN_ID names a run of an earlier proof run: exactly one DIR/proof-*/project/.factory/runs/RUN_ID must
# hold it, or the script refuses before it makes anything.
# --continue RUN_ID continues a run that stopped or paused, in the proof folder under DIR that holds it (the setup
# flags are refused: the run keeps its config). It checks the credentials and runs `ygg doctor`, then `ygg approve
# RUN_ID GATE --project P [--note TEXT]`, `ygg reject RUN_ID GATE --reason TEXT --project P` or `ygg resume RUN_ID
# --project P` as step 7 runs `ygg run` (the same timeout, the credentials in that subshell only, the filter, the
# output added to run.txt; --decisions FILE gives the gate's decisions as a file, in place of --note or --reason: the
# script refuses the pair, and a file that is missing, and passes the file as an absolute path, made from the caller's
# folder; a rejection may take a file and no reason; a rejection advances the run at once, so it starts sessions as an
# approval does), then
# steps 8 and 9, with the baseline the proof run recorded unless --baseline names another. The raw `ygg approve`,
# `ygg reject` and `ygg resume` commands are printed too, as a fallback: they run without the wall clock, the filter
# or the report.
# The stale-binary guard: when YGG_CMD is not set, the ygg on PATH must have build facts (BINARY.build.txt, written by
# scripts/ygg-build.sh) that name the HEAD of the umbrella's odin (--yggdrasil DIR/odin) and the binary's SHA-256.
# A ygg with no facts, or other ones, is refused before anything is made ("run scripts/ygg-build.sh"); --any-ygg
# skips the check and says so; a dry run prints the result and is not refused.
# For tests and other machines: YGG_CMD (how ygg runs), YGG_BIND (the bind mount, default /mnt/wsl/ygg-bind).
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=ygg-build-facts.sh
. "$HERE/ygg-build-facts.sh"
usage() {
  echo "usage: ygg-proof-run.sh --name NAME [--mode MODE] [--planner|--implementer|--reviewer AGENT:MODEL] [--models FILE] [--retro-agent AGENT] [--retro-model MODEL] [--reviewer-reasoning low|medium|high|off] [--run-turns|--run-tokens|--run-usd|--day-turns|--day-tokens|--day-usd N] [--baseline RUN_ID] [--dry-run] [--build] [--folder DIR] [--env FILE] [--tasks DIR] [--suites DIR] [--yggdrasil DIR] [--wall TIME] [--clip] [--any-ygg]" >&2
  echo "       ygg-proof-run.sh --continue RUN_ID (--approve GATE [--note TEXT | --decisions FILE] | --reject GATE (--reason TEXT | --decisions FILE) | --resume)" >&2
  echo "                        [--baseline RUN_ID] [--dry-run] [--folder DIR] [--env FILE] [--wall TIME] [--clip] [--any-ygg]" >&2
  exit 2
}
fail() { echo "proof-run: $*" >&2; exit 2; }
# Only the script's own files are private (the credentials' values never reach them, but they hold the run's output).
# Everything else (the project, its git repository and what ygg makes, which the sandboxes read) keeps the caller's
# umask, as in the smoke scripts: no umask is set for the whole script.
private() { (umask 077 && : >>"$1") && chmod 600 "$1"; } # FILE: made private; what it holds stays
put() { (umask 077 && printf '%s\n' "$2" >"$1"); }         # FILE TEXT: a small control file, private
models="" name="" mode=key-points dry=0 build=0 clip=0 baseline="" wall=8h any_ygg=0
# --continue; setup_flags are the setup flags given (a continued run keeps its config)
cont="" gate_in="" reject_in="" reason="" reason_set=0 note="" note_set=0 resume=0 setup_flags=""
decisions="" decisions_set=0
planner=claude-code:sonnet implementer=claude-code:sonnet reviewer=opencode:openrouter/qwen/qwen3.8-27b
reviewer_reasoning=medium retro_agent=claude-code retro_model=opus
run_turns=1500 run_tokens=12000000 run_usd=5 day_turns=2000 day_tokens=24000000 day_usd=10
dir="$HOME/ygg-it" envfile="$HOME/.config/ouroboric/factory.env" tasks="$HERE/../../mimir"
suites="$HOME/ygg-it/hidden-suites" ygg_dir="$HERE/../../yggdrasil"
while [ $# -gt 0 ]; do
  case "$1" in
    --name | --mode | --planner | --implementer | --reviewer | --models | --reviewer-reasoning | --retro-* | --run-* | --day-* | --build | --tasks | --suites | --yggdrasil) setup_flags+=" $1" ;;
  esac
  case "$1" in
    --dry-run) dry=1; shift ;;
    --any-ygg) any_ygg=1; shift ;;
    --build) build=1; shift ;;
    --resume) resume=1; shift ;;
    --continue) [ $# -ge 2 ] || usage; cont="$2"; shift 2 ;;
    --approve) [ $# -ge 2 ] || usage; gate_in="$2"; shift 2 ;;
    --reject) [ $# -ge 2 ] || usage; reject_in="$2"; shift 2 ;;
    --reason) [ $# -ge 2 ] || usage; reason="$2"; reason_set=1; shift 2 ;;
    --note) [ $# -ge 2 ] || usage; note="$2"; note_set=1; shift 2 ;;
    --decisions) [ $# -ge 2 ] || usage; decisions="$2"; decisions_set=1; shift 2 ;;
    --retro-agent) [ $# -ge 2 ] || usage; retro_agent="$2"; shift 2 ;;
    --retro-model) [ $# -ge 2 ] || usage; retro_model="$2"; shift 2 ;;
    --clip) clip=1; shift ;;
    --name) [ $# -ge 2 ] || usage; name="$2"; shift 2 ;;
    --mode) [ $# -ge 2 ] || usage; mode="$2"; shift 2 ;;
    --planner) [ $# -ge 2 ] || usage; planner="$2"; shift 2 ;;
    --implementer) [ $# -ge 2 ] || usage; implementer="$2"; shift 2 ;;
    --reviewer) [ $# -ge 2 ] || usage; reviewer="$2"; shift 2 ;;
    --models) [ $# -ge 2 ] || usage; models="$2"; shift 2 ;;
    --reviewer-reasoning) [ $# -ge 2 ] || usage; reviewer_reasoning="$2"; shift 2 ;;
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
run_id_re='^[A-Za-z0-9][A-Za-z0-9._-]*$' # a run id is a folder name: never . or ..
if [ -n "$cont" ]; then
  [[ $cont =~ $run_id_re ]] || fail "--continue '$cont' is not a run id"
  [ -z "$setup_flags" ] || fail "--continue keeps the config of the run's proof folder; it takes none of$setup_flags"
  actions=0
  [ -z "$gate_in" ] || actions=$((actions + 1))
  [ -z "$reject_in" ] || actions=$((actions + 1))
  [ "$resume" -eq 0 ] || actions=$((actions + 1))
  if [ "$actions" -gt 1 ]; then fail "--continue takes --approve GATE, --reject GATE --reason TEXT or --resume, only one"; fi
  if [ "$actions" -eq 0 ]; then fail "--continue takes --approve GATE, --reject GATE --reason TEXT or --resume"; fi
  if [ "$decisions_set" -eq 1 ] && [ -z "$gate_in" ] && [ -z "$reject_in" ]; then fail "--decisions goes with --approve or --reject"; fi
  if [ "$decisions_set" -eq 1 ] && { [ "$note_set" -eq 1 ] || [ "$reason_set" -eq 1 ]; }; then fail "--decisions replaces --note and --reason; give the file or the text, not both"; fi
  if [ -n "$gate_in" ] && ! [[ $gate_in =~ $run_id_re ]]; then fail "--approve '$gate_in' is not a gate name"; fi
  if [ -n "$reject_in" ] && ! [[ $reject_in =~ $run_id_re ]]; then fail "--reject '$reject_in' is not a gate name"; fi
  if [ "$note_set" -eq 1 ] && [ -z "$gate_in" ]; then fail "--note goes with --approve"; fi
  if [ "$reason_set" -eq 1 ] && [ -z "$reject_in" ]; then fail "--reason goes with --reject"; fi
  if [ -n "$reject_in" ] && [ "$reason_set" -eq 0 ] && [ "$decisions_set" -eq 0 ]; then fail "--reject needs --reason TEXT or --decisions FILE: the reason goes to the agents"; fi
  if [ "$decisions_set" -eq 1 ]; then
    # The file is passed as an absolute path, made from the caller's folder: ygg runs from another one.
    [ -n "$decisions" ] || fail "--decisions is empty; it names a decisions file"
    [ -f "$decisions" ] || fail "--decisions $decisions: no such file"
    decisions_dir="$(cd -P -- "$(dirname -- "$decisions")" 2>/dev/null && pwd -P)" || fail "--decisions $decisions: no such file"
    decisions="$decisions_dir/$(basename -- "$decisions")"
  fi
  # U+2028, U+2029 and the C1 controls U+0080 to U+009F (odin refuses them) are matched as bytes, so the locale does not decide.
  sep_line=$'\xe2\x80\xa8' sep_para=$'\xe2\x80\xa9'
  c1_re=$'\xc2[\x80-\x9f]'
  if [[ $decisions == *[[:cntrl:]]* || $decisions == *"$sep_line"* || $decisions == *"$sep_para"* || $decisions =~ $c1_re ]]; then fail "--decisions has a control character (or U+2028, U+2029, a C1 control) in its path"; fi
  if [[ $note == *[[:cntrl:]]* || $note == *"$sep_line"* || $note == *"$sep_para"* || $note =~ $c1_re ]]; then fail "--note has a control character (or U+2028, U+2029, a C1 control); a note is one line of text"; fi
  if [[ $reason == *[[:cntrl:]]* || $reason == *"$sep_line"* || $reason == *"$sep_para"* || $reason =~ $c1_re ]]; then fail "--reason has a control character (or U+2028, U+2029, a C1 control); a reason is one line of text"; fi
  if [ "$reason_set" -eq 1 ] && [[ $reason =~ ^[[:space:]]*$ ]]; then fail "--reason is blank; say why the gate is rejected"; fi
else
  if [ -n "$gate_in" ] || [ -n "$reject_in" ] || [ "$resume" -eq 1 ] || [ "$note_set" -eq 1 ] || [ "$reason_set" -eq 1 ] || [ "$decisions_set" -eq 1 ]; then
    fail "--approve, --reject, --reason, --resume, --note and --decisions go with --continue RUN_ID"
  fi
  [ -n "$name" ] || fail "--name is needed: the run's name, such as baseline-1"
  [[ $name =~ ^[a-z0-9-]+$ ]] || fail "--name '$name' has characters outside a-z0-9-"
  case "$mode" in key-points | unattended | step-by-step) ;; *) fail "--mode is key-points, unattended or step-by-step, not '$mode'" ;; esac
  case "$reviewer_reasoning" in low | medium | high | off) ;; *) fail "--reviewer-reasoning is low, medium, high or off, not '$reviewer_reasoning'" ;; esac
  for pair in run-turns:"$run_turns" run-tokens:"$run_tokens" day-turns:"$day_turns" day-tokens:"$day_tokens"; do
    [[ ${pair#*:} =~ ^[1-9][0-9]*$ ]] || fail "--${pair%%:*} is a whole number above 0, not '${pair#*:}'"
  done
  for pair in run-usd:"$run_usd" day-usd:"$day_usd"; do
    [[ ${pair#*:} =~ ^[0-9]+(\.[0-9]+)?$ ]] || fail "--${pair%%:*} is a number of dollars such as 5 or 2.5, not '${pair#*:}'"
  done
fi
[[ $wall =~ ^[1-9][0-9]*[smh]$ ]] || fail "--wall is a number and s, m or h, such as 8h"
if [ -n "$baseline" ]; then [[ $baseline =~ $run_id_re ]] || fail "--baseline '$baseline' is not a run id"; fi
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
    opencode)
      if [[ $model == local/* ]]; then
        [[ ${model#local/} =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || fail "$flag: a local MODEL is local/<name>, with a name of a-z0-9._- that starts with a-z0-9 (at most 64), such as opencode:local/qwen3.8-27b"
      else
        [[ $model == openrouter/?* ]] || fail "$flag: an opencode MODEL is openrouter/<model> or local/<name>, such as opencode:openrouter/qwen/qwen3.8-27b"
      fi ;;
    *) fail "$flag is AGENT:MODEL, with AGENT claude-code or opencode, not '$agent'" ;;
  esac
}
roles_ok() { # sets paid, need_claude, need_router and need_local
  role_ok --planner "$planner"; role_ok --implementer "$implementer"; role_ok --reviewer "$reviewer"
  # A proof folder from before the retrospective role has none: retro stays empty and the role is left out.
  retro=""
  if [ -n "$retro_agent$retro_model" ]; then
    [[ $retro_agent != *:* ]] || fail "--retro-agent is claude-code or opencode, not '$retro_agent'"
    retro="$retro_agent:$retro_model"
    role_ok --retro-agent/--retro-model "$retro"
  fi
  paid=0 need_claude=0 need_router=0 need_local=0
  local_models=""
  for r in "$planner" "$implementer" "$reviewer" ${retro:+"$retro"}; do
    case "${r%%:*}" in
      claude-code) need_claude=1 ;;
      opencode) if [[ ${r#*:} == local/* ]]; then need_local=1; local_models+="${r#*:}"$'\n'; else need_router=1; paid=1; fi ;;
    esac
  done
  # The server holds one model at a time (spec 5.2.1): roles on two local models are refused before anything is made.
  [ "$(printf '%s' "$local_models" | sort -u | grep -c .)" -le 1 ] || fail "roles on two different local models ($(printf '%s' "$local_models" | sort -u | paste -sd' ')): the local model server holds one; name the same local/<name> for every local role"
  # A local reviewer sets no reasoning (ygg refuses it): --reviewer-reasoning does not apply to it.
  reviewer_is_local=0
  [[ ${reviewer#*:} != local/* ]] || reviewer_is_local=1
}
[ -n "$cont" ] || roles_ok
if [ -z "$cont" ]; then
  # The model list: needed by a local role, and only then. The config takes a clean absolute path.
  if [ "$need_local" -eq 1 ] && [ -z "$models" ]; then fail "a role is on a local model (opencode:local/<name>): --models FILE, the model list, is needed"; fi
  if [ "$need_local" -eq 0 ] && [ -n "$models" ]; then fail "--models goes with a role on a local model (opencode:local/<name>); no role is on one"; fi
  if [ -n "$models" ]; then
    [ -f "$models" ] || fail "--models $models: no such file"
    models="$(readlink -f -- "$models")"
    safe_path --models "$models"
  fi
fi

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

# A run of an earlier proof run, by its id: exactly one proof folder under DIR may hold it. Each proof run has its
# own project, so a run is found by its folder name and nothing else; no run folder is read here.
find_run() { # FLAG RUN_ID: sets hit to that run's folder, or sets why and returns 1
  local h
  local -a hits=()
  for h in "$dir_abs"/proof-*/project/.factory/runs/"$2"; do [ -d "$h" ] && hits+=("$h"); done
  hit="${hits[0]:-}"
  case "${#hits[@]}" in
    1) return 0 ;;
    0) why="$1: no proof folder under $dir_abs holds a run $2" ;;
    *) why="$1: ${#hits[@]} proof folders under $dir_abs hold a run $2 (${hits[*]%/project/.factory/runs/*}); a run id must name one run" ;;
  esac
  return 1
}
baseline_recorded=0
if [ -z "$cont" ]; then
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
else
  # 2. and 3. for --continue: the proof folder that holds the run, and what its setup recorded. The task, the suites
  # and the config were checked when the run was set up; the config stays as it was.
  dir_abs="$(cd -P -- "$dir" 2>/dev/null && pwd -P)" || fail "no folder at $dir (--folder)"
  safe_path "--folder (resolved)" "$dir_abs"
  find_run --continue "$cont" || fail "$why"
  work="${hit%/project/.factory/runs/*}"
  [[ ${work##*/} =~ ^proof-[a-z0-9-]+-[0-9]{8}-[0-9]{6}$ ]] || fail "$work is not a proof folder (proof-NAME-TIME)"
  [ -f "$work/factory.yaml" ] && [ -f "$work/proof.meta" ] || fail "$work has no factory.yaml or proof.meta: this script did not set it up"
  meta() { sed -n "s/^$1 //p" "$work/proof.meta" | head -n 1; } # a key's value; each is checked below as a flag is
  name="$(meta name)" mode="$(meta mode)" planner="$(meta planner)" implementer="$(meta implementer)" reviewer="$(meta reviewer)"
  reviewer_reasoning="$(meta reviewer_reasoning)"
  retro="$(meta retrospective)" retro_agent="" retro_model=""
  if [ -n "$retro" ]; then retro_agent="${retro%%:*}" retro_model="${retro#*:}"; fi
  task="$(meta task)" suite="$(meta suite)" have="$(meta brief)"
  [[ $name =~ ^[a-z0-9-]+$ ]] || fail "$work/proof.meta has no proof run name"
  case "$mode" in key-points | unattended | step-by-step) ;; *) fail "$work/proof.meta has no mode" ;; esac
  # A folder from before --reviewer-reasoning has no such line: its factory.yaml is written, so the value is only shown.
  if ! grep -q '^reviewer_reasoning ' "$work/proof.meta"; then reviewer_reasoning="unset"
  else case "$reviewer_reasoning" in low | medium | high | off) ;; *) fail "$work/proof.meta has no valid reviewer reasoning" ;; esac; fi
  roles_ok
  [[ $task =~ ^[A-Za-z0-9._-]+$ && $suite =~ ^[a-z0-9][a-z0-9._-]*$ && $have =~ ^[0-9a-f]{64}$ ]] || fail "$work/proof.meta has no task, suite or brief SHA-256"
  if [ -z "$baseline" ]; then
    baseline="$(meta baseline)" baseline_recorded=1
    if [ -n "$baseline" ] && ! [[ $baseline =~ $run_id_re ]]; then fail "$work/proof.meta records a baseline that is not a run id"; fi
  fi
  if [ "$baseline" = "$cont" ]; then fail "--baseline $baseline is the run being continued; a run is not its own baseline"; fi
fi
# The stale-binary guard, before anything is made or run: only a ygg from PATH (YGG_CMD is not guarded).
if [ -z "${YGG_CMD:-}" ]; then
  guard_odin="$(cd -P -- "$ygg_dir/odin" 2>/dev/null && pwd -P || echo "$ygg_dir/odin")"
  ygg_guard proof-run "$guard_odin" "$any_ygg" "$dry" || exit 2
fi
# The baseline, found before anything is made or started: a bad one costs nothing. A baseline the proof run recorded
# that is gone now only drops the comparison, so that the run can still be continued.
base_dir=""
if [ -n "$baseline" ]; then
  if find_run --baseline "$baseline"; then base_dir="$hit"
  elif [ "$baseline_recorded" -eq 1 ]; then echo "proof-run: $why; the comparison is left out" >&2; baseline=""
  else fail "$why"
  fi
fi

# 4. The credentials, by name. grep -c prints a count and nothing else; no line is shown, stored or compared.
[ -f "$envfile" ] || fail "the credentials file $envfile is missing"
names=()
[ "$need_claude" -eq 0 ] || names+=(CLAUDE_CODE_OAUTH_TOKEN)
[ "$need_router" -eq 0 ] || names+=(OPENROUTER_API_KEY)
for n_ in ${names[@]+"${names[@]}"}; do
  n="$(grep -c -E "^(export[[:space:]]+)?${n_}=[^[:space:]]" "$envfile" || true)"
  [ "$n" = 1 ] || fail "$envfile has $n line(s) that set $n_ with a value; the roles need exactly 1"
done

if [ -z "$cont" ]; then
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
  if [ "$reviewer_is_local" -eq 1 ]; then fill REVIEWER_REASONING ""; else fill REVIEWER_REASONING ", reasoning: $reviewer_reasoning"; fi
  fill RETRO_AGENT "$retro_agent"; fill RETRO_MODEL "$retro_model"
  fill RUN_TOKENS "$run_tokens"; fill RUN_TURNS "$run_turns"; fill RUN_USD "$usd_run"
  fill DAY_TOKENS "$day_tokens"; fill DAY_TURNS "$day_turns"; fill DAY_USD "$usd_day"
  fill ENGINE "$engine"; fill FOLDER "$dir_abs"; fill BIND "${YGG_BIND:-/mnt/wsl/ygg-bind}"
  fill REALMS "$ygg_dir"; fill GRAPHS "$ygg_dir/voluspa"
  fill TASKS "$tasks"; fill SUITES "$suites"
  if [ "$need_local" -eq 1 ]; then text+=$'\nmodels:\n'"  file: $models"; fi
  printf '%s\n' "$text" >"$work/factory.yaml"
  if grep -q '@[A-Z_]*@' "$work/factory.yaml"; then fail "$work/factory.yaml still has a place to fill: $(grep -o '@[A-Z_]*@' "$work/factory.yaml" | sort -u | tr '\n' ' ')"; fi
  echo "proof-run: made $work"
  echo "proof-run: the task is $task, suite $suite; the brief is the frozen one (SHA-256 $have)"
  [ "$reviewer_is_local" -eq 0 ] || echo "proof-run: the reviewer is a local model, so its reasoning is left out of the config (--reviewer-reasoning does not apply)"
  [ "$need_local" -eq 0 ] || echo "proof-run: the model list is $models (models.file)"
  [ "$paid" -eq 1 ] || echo "proof-run: no role is paid per token, so the config has no usd line"
  # What --continue needs to know about this proof run, one "key value" a line; every value was checked above.
  private "$work/proof.meta"
  printf 'name %s\nmode %s\nplanner %s\nimplementer %s\nreviewer %s\nreviewer_reasoning %s\nretrospective %s\ntask %s\nsuite %s\nbrief %s\nbaseline %s\n' \
    "$name" "$mode" "$planner" "$implementer" "$reviewer" "$reviewer_reasoning" "$retro" "$task" "$suite" "$have" "$baseline" >"$work/proof.meta"
else
  project="$work/project"
  echo "proof-run: continuing run $cont of the proof run $name in $work"
  echo "proof-run: the task is $task, suite $suite; the brief's SHA-256 was $have"
fi

# 6. doctor, and the plan.
echo "proof-run: ygg doctor on that config"
if ! "${ygg_arr[@]}" doctor --project "$project" --config "$work/factory.yaml"; then fail "ygg doctor refused the config; nothing was spent"; fi
# Commands are printed with %q and never run through eval.
q() { printf '%q ' "$@"; }
qt() { local t; t="$(q "$@")"; printf '%s' "${t% }"; } # q without its last space
cont_what="" # for --continue: what the continuation does
if [ -z "$cont" ]; then
  run_argv=("${ygg_arr[@]}" run --project "$project" --config "$work/factory.yaml" --graph software --brief "$tasks/$task/instruction.md" --mode "$mode")
elif [ -n "$gate_in" ]; then
  run_argv=("${ygg_arr[@]}" approve "$cont" "$gate_in" --project "$project")
  [ "$note_set" -eq 0 ] || run_argv+=(--note "$note")
  [ "$decisions_set" -eq 0 ] || run_argv+=(--decisions "$decisions")
  cont_what="approve $gate_in"
elif [ -n "$reject_in" ]; then
  if [ "$decisions_set" -eq 1 ]; then run_argv=("${ygg_arr[@]}" reject "$cont" "$reject_in" --project "$project" --decisions "$decisions")
  else run_argv=("${ygg_arr[@]}" reject "$cont" "$reject_in" --reason "$reason" --project "$project"); fi
  cont_what="reject $reject_in"
else
  run_argv=("${ygg_arr[@]}" resume "$cont" --project "$project")
  cont_what="resume"
fi
build_argv=("${ygg_arr[@]}" sandbox build --all --config "$work/factory.yaml")
run_cmd="$(q "${run_argv[@]}")"
build_cmd="$(q "${build_argv[@]}")"
timeout_argv=(timeout --signal=INT --kill-after=2m "$wall")
reasoning_note="" # for an old folder, why the reasoning is unset
[ "$reviewer_reasoning" != unset ] || reasoning_note=": a folder from before --reviewer-reasoning"
reasoning_desc="reasoning $reviewer_reasoning${reasoning_note}"
[ "$reviewer_is_local" -eq 0 ] || reasoning_desc="no reasoning: a local model sets none"
echo "proof-run: the plan: mode $mode; planner $planner, implementer $implementer, reviewer $reviewer ($reasoning_desc)${retro:+; retrospective $retro}"
echo "proof-run: the caps in $work/factory.yaml:"
{ grep -E '^  per_(run|day):' "$work/factory.yaml" || true; } | sed 's/^/  /'
[ -z "$cont_what" ] || echo "proof-run: the continuation: $cont_what"
[ -z "$baseline" ] || echo "proof-run: after the run: compare with the baseline run $baseline, in ${base_dir%/.factory/runs/*}"
[ "$clip" -eq 0 ] || echo "proof-run: after the run: the report is copied to the clipboard"
if [ "$dry" -eq 1 ]; then
  [ "$build" -eq 0 ] || echo "proof-run: would run: $build_cmd"
  echo "proof-run: would run: $(q "${timeout_argv[@]}")$run_cmd"
  echo "proof-run: dry run: nothing was started and the credentials were not loaded"
  exit 0
fi

# 7. The run. Only `ygg run` starts model sessions, so only it (and the output filter, which needs the exact values
# to remove them) gets the credentials: each is sourced in its own subshell and nothing is exported by this shell.
load_env() { # in a subshell only
  { set +x; } 2>/dev/null # no trace of the sourced assignments, even under bash -x or SHELLOPTS=xtrace
  set -a
  # shellcheck source=/dev/null
  # The source's own stderr is silenced: on a syntax error bash prints the offending line, which can hold a secret.
  . "$envfile" 2>/dev/null || { echo "proof-run: the credentials file could not be read" >&2; return 1; }
  set +a
}
# The filter works on bytes (any byte survives), replaces the exact values, and if it cannot run it drains its input
# so the writer is never killed by SIGPIPE: the output is then withheld, not shown unfiltered.
redact() {
  (
    # shellcheck disable=SC2015 # the fallback is for both: the load failing and the filter failing
    load_env && python3 -I -u -c '
import os, re, sys
name = re.compile(rb"TOKEN|KEY|SECRET|PASSWORD|CREDENTIAL", re.I)
vals = sorted({v for k, v in os.environb.items() if name.search(k) and len(v) >= 8}, key=len, reverse=True)
if not vals:
    sys.exit(1)  # no value to remove: fail closed
out = sys.stdout.buffer
for line in sys.stdin.buffer:
    for v in vals:
        line = line.replace(v, b"[REDACTED]")
    out.write(line)
    out.flush()
' || { echo "proof-run: the output filter failed or the credentials could not be loaded; the output is withheld" >&2; cat >/dev/null; }
  )
}
# The run alone has the credentials. timeout is not --foreground: it gets its own process group and, at the wall clock
# (INT, then KILL after the grace period) or when it is signalled, relays the signal to that whole group: ygg and the
# model sessions it starts. The sandboxes are not in that group: they run under the container engine (conmon), and
# ygg stops them on a clean stop; after an abnormal end (the wall clock, a kill) step 8 runs `ygg doctor`, which finds
# and stops what is left. A terminal's Ctrl-C (INT) or hang-up (HUP) goes to this script's whole process group, not
# to timeout's: the pipeline below ignores both, so the filter and tee keep reading until the run ends, and only the
# trap's forward reaches ygg, once. timeout runs in the background of its subshell and its pid is kept, so that a
# signal to this script (which bash would only handle after the pipeline) is passed on to it. timeout sets its own
# handlers, so ygg starts with INT and HUP at their defaults. The trap also leaves a stop flag: a signal that comes
# before the pid exists (during the build) is not lost, the build is stopped and no run is started.
run_part() {
  stopped() { [ -f "$work/run.stop" ]; }
  stop_rc() { case "$(cat "$work/run.stop")" in INT) echo 130 ;; HUP) echo 129 ;; *) echo 143 ;; esac; }
  if [ "$build" -eq 1 ] && ! stopped; then
    "${build_argv[@]}" &
    bp=$!
    put "$work/build.pid" "$bp"
    if stopped; then kill -s TERM "$bp" 2>/dev/null; fi
    wait "$bp" || { stopped || { put "$work/run.rc" 2; return 0; }; }
  fi
  if stopped; then
    echo "proof-run: stopped by a signal; the run was not started"
    put "$work/run.rc" "$(stop_rc)"
    return 0
  fi
  [ -z "$cont_what" ] || echo "proof-run: continuing run $cont: $cont_what"
  (
    load_env || { put "$work/run.rc" 2; exit 0; }
    "${timeout_argv[@]}" "${run_argv[@]}" &
    tp=$!
    put "$work/run.pid" "$tp"
    if stopped; then kill -s "$(cat "$work/run.stop")" "$tp" 2>/dev/null; fi
    wait "$tp"
    put "$work/run.rc" "$?"
  )
}
out="$work/run.txt" # a continuation adds to it
if [ -z "$cont" ]; then echo "proof-run: starting the run (wall clock $wall); this costs money"
else echo "proof-run: continuing the run (wall clock $wall); this costs money"; fi
set +e
rm -f "$work/run.pid" "$work/run.rc" "$work/run.stop" "$work/run.hup" "$work/build.pid"
# shellcheck disable=SC2329 # called by the traps
on_signal() { # SIGNAL: leave the stop flag, then pass the signal to the build or to timeout (and so to ygg)
  local p f
  [ -f "$work/run.stop" ] || put "$work/run.stop" "$1" # the first signal sets the exit code of a stop
  [ "$1" != HUP ] || put "$work/run.hup" HUP             # a hang-up is kept on its own: it can follow a Ctrl-C
  # The build starts with SIGINT and SIGHUP ignored (an async job, in the pipeline): it gets TERM for any signal.
  p="$(cat "$work/build.pid" 2>/dev/null)" || p=""
  [ -z "$p" ] || kill -s TERM "$p" 2>/dev/null
  p="$(cat "$work/run.pid" 2>/dev/null)" || p=""
  [ -z "$p" ] || kill -s "$1" "$p" 2>/dev/null
  return 0
}
trap 'on_signal TERM' TERM
trap 'on_signal INT' INT
trap 'on_signal HUP' HUP
private "$out"
(trap '' INT HUP; run_part 2>&1 | redact | tee -a "$out") &
pl=$!
while kill -0 "$pl" 2>/dev/null; do wait "$pl"; done
trap - TERM INT
trap '' HUP # the run is over: a hang-up from now on does not cut the report short
rm -f "$work/run.pid" "$work/build.pid"
# After a hang-up (alone, or after a Ctrl-C or TERM) the terminal is gone and every write to it fails: what is still
# printed is kept in hangup.txt.
if [ -f "$work/run.hup" ]; then private "$work/hangup.txt"; exec >>"$work/hangup.txt" 2>&1; fi
set -e
rc="$(cat "$work/run.rc" 2>/dev/null || echo 2)"
[[ $rc =~ ^[0-9]+$ ]] || rc=2
echo "proof-run: the run ended with exit code $rc (0 done, 1 a node failed, 2 refused, 3 stopped, 4 paused, 5 done with tasks given up, 124 the wall clock, 129, 130 or 143 ended by HUP, INT or TERM, 137 killed after the grace period, 141 SIGPIPE)"

# 8. The evidence. The graph ends with a grade node and then a retro node, and the factory.yaml has a grader section,
# so the run grades itself and its retro follows: this script never runs `ygg grade`. The run's id is the one continued, or the newest folder in the project's runs. None
# of these needs a credential; the filter removes the exact values anyway, from anything a tool prints.
if [ -n "$cont" ]; then id="$cont"
else id="$(find "$project/.factory/runs" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n 1 || true)"; fi
report="$work/report.txt"
if [ -z "$id" ] || ! [[ $id =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "proof-run: the run left no run folder in $project/.factory/runs; nothing to report" >&2
  echo "proof-run: the folder is $work"
  exit "$rc"
fi
step() { # TITLE CMD...: a heading, then the command's output; its exit code is noted, never fatal
  echo "## $1"; shift
  "$@" || echo "(exited $?)"
  echo
}
evidence_part() {
  echo "# proof run $name: run $id, exit code $rc${cont_what:+ (continued: $cont_what)}"
  echo "mode $mode; planner $planner, implementer $implementer, reviewer $reviewer ($reasoning_desc); brief SHA-256 $have"
  echo
  case "$rc" in
    0 | 3 | 4 | 5) ;;
    *) step "ygg doctor (an abnormal end: it finds and stops what the run left)" "${ygg_arr[@]}" doctor --project "$project" --config "$work/factory.yaml" ;;
  esac
  step "ygg metrics" "${ygg_arr[@]}" metrics "$id" --project "$project"
  if [ -n "$baseline" ] && [ "$baseline" = "$id" ]; then
    printf '## ygg metrics --compare\n(not run: the baseline is this run)\n\n'
  elif [ -n "$baseline" ]; then
    # ygg compares two runs of one project, and each proof run has its own: both run folders are linked into one.
    (umask 077 && mkdir -p "$work/compare/.factory/runs")
    ln -sfn "$base_dir" "$work/compare/.factory/runs/$baseline"
    ln -sfn "$project/.factory/runs/$id" "$work/compare/.factory/runs/$id"
    step "ygg metrics --compare $baseline $id" "${ygg_arr[@]}" metrics --compare "$baseline" "$id" --project "$work/compare"
  fi
  step "ygg report" "${ygg_arr[@]}" report "$id" --project "$project"
  # The record is for a run that is done; it is written again, with the judgement, by `ygg score`.
  case "$rc" in 0 | 5) step "ygg record" "${ygg_arr[@]}" record "$id" --project "$project" ;; esac
  if [ -f "$project/.factory/runs/$id/ledger.jsonl" ]; then
    step "cost" "$HERE/ygg-cost.sh" "$project/.factory/runs/$id/ledger.jsonl" "$work/factory.yaml"
    step "evidence" env YGG_CMD="$ygg" "$HERE/ygg-evidence.sh" --output "$out" "$project" "$id"
  fi
}
set +e # nothing after the run may change the run's exit code
rep_start=0 # a continuation adds its report to report.txt; --clip copies the new one
[ ! -f "$report" ] || rep_start="$(wc -c <"$report")"
private "$report"
evidence_part 2>&1 | redact | tee -a "$report" || true
if [ "$clip" -eq 1 ]; then
  if command -v clip.exe >/dev/null 2>&1 && [ -f "$report" ]; then tail -c +"$((rep_start + 1))" "$report" | clip.exe; echo "proof-run: the report copied to the clipboard"
  else echo "proof-run: --clip needs clip.exe (WSL); the report is in $report" >&2; fi
fi
echo "proof-run: the folder is $work"

# After a run that ended 0 or 5 (done, with or without tasks given up): where the record is, and the line to judge the
# run with. Nothing of the kind after a stop, a pause or a failure: that run can still go on.
if [ "$rc" -eq 0 ] || [ "$rc" -eq 5 ]; then
  echo "proof-run: the run is done; its record is $project/.factory/runs/$id/record.json"
  echo "proof-run: judge it (a score from 0 to 10, and what went well and what went wrong), then run:"
  echo "  $(q "${ygg_arr[@]}")score $(qt "$id") --score N --well \"…\" --wrong \"…\" $(q --project "$project")"
fi

# 9. How to continue a run that stopped or paused: this script's --continue, which keeps the wall clock, the filter,
# run.txt and the report. The raw ygg command is printed first, as a fallback. The last line is the --continue command.
self=("$HERE/ygg-proof-run.sh" --continue "$id")
by_hand="proof-run: or by hand, outside this script (no wall clock, no filter, no run.txt or report; load the credentials in that shell first):"
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
    echo "$by_hand"
    echo "  $(q "$HERE/ygg-engine.sh" run --folder "$dir_abs" -- "${ygg_arr[@]}" approve "$id" "$gate" --project "$project")"
    echo "  $(qt "$HERE/ygg-engine.sh" run --folder "$dir_abs" -- "${ygg_arr[@]}" reject "$id" "$gate") --reason \"...\" $(q --project "$project")"
    echo "proof-run: the run stopped at $gate; read its gates folder. If ygg offered a rejection above, reject it with a reason, or --decisions FILE in its place:"
    echo "  $(qt "${self[@]}" --reject "$gate") --reason \"...\" $(q --folder "$dir_abs" --env "$envfile")"
    echo "proof-run: or approve it (add --note TEXT or --decisions FILE if you like; some stops take no rejection or no approval):"
    echo "  $(q "${self[@]}" --approve "$gate" --folder "$dir_abs" --env "$envfile")"
    ;;
  4)
    echo "$by_hand"
    echo "  $(q "$HERE/ygg-engine.sh" run --folder "$dir_abs" -- "${ygg_arr[@]}" resume "$id" --project "$project")"
    echo "proof-run: the run paused (the provider's quota); once it is back, continue it:"
    echo "  $(q "${self[@]}" --resume --folder "$dir_abs" --env "$envfile")"
    ;;
esac
exit "$rc"

#!/usr/bin/env bash
# Run the real-agent smoke (v0-H17): the task smoke-notes built by the real Claude Code and the real OpenCode on
# OpenRouter, then graded. IT COSTS MONEY: the caps are in odin/testdata/smoke-grade/factory.real.example.yaml.
#   ygg-smoke-real.sh [--dry-run] [--build] [--folder DIR] [--env FILE] [--tasks DIR] [--odin DIR] [--wall TIME] [--clip]
#                     [--from-leaf LEAF] [--implementer AGENT:MODEL] [--models FILE] [--brief-note FILE] [--any-ygg]
# The suite is the PUBLIC sample suite of the task (no hidden suite of smoke-notes exists); the agents never mount
# it. Needs DIR/factory.yaml (it names the engine; this script never writes it), the credentials file, the
# devcontainer CLI 0.89.0, jq and python3, the engine up, the bind mount present, and a checkout of `mimir`. It
#   1. checks the engine, the tools and the task, and that a ygg from PATH is not stale: when neither YGG_CMD nor a
#      build from --odin gives the ygg, its build facts (BINARY.build.txt, written by scripts/ygg-build.sh) must name
#      the HEAD of the odin checkout and the binary's SHA-256. A ygg with no facts, or other ones, is refused
#      ("run scripts/ygg-build.sh"); --any-ygg skips the check and says so; a dry run prints the result only;
#   2. checks the credentials file WITHOUT reading it: the file exists, and each name the roles need is on one line
#      with a value after it (grep -c counts the lines; no value is printed or kept). A claude-code role needs
#      CLAUDE_CODE_OAUTH_TOKEN and an opencode role on openrouter/... needs OPENROUTER_API_KEY; a local role needs
#      none. The roles are the example's, with --implementer applied. If none is on OpenRouter, the "usd" caps
#      are taken out of the config (only a paid API bills dollars);
#   3. makes DIR/smoke-real-<time> with the project, the public suite and the factory.yaml filled from the
#      example (its caps are the real ones). With --implementer AGENT:MODEL, its implementer line is replaced
#      (AGENT is claude-code or opencode; an opencode MODEL is openrouter/<model> or local/<name>, a model of the
#      operator's model list), so one role changes (B-110). A local role needs --models FILE, the model list: the
#      config then ends with `models:` and `  file: FILE`. FILE must exist; a relative path is made absolute from
#      the caller's folder. A local role without --models is refused before anything is made, and so is --models
#      when no role is local, and so are roles on two different local models. A local role sets no `reasoning` (the example's roles have none);
#      With --from-leaf LEAF, the leaf repos/notes starts from the files of LEAF (without .git) instead of the
#      pack's template (B-109): the pack is copied to DIR/smoke-real-<time>/pack, LEAF becomes the copy's
#      template, and every file of LEAF goes in the leaf's first commit. odin writes those files without the
#      execute bit, so the project's start.sh then runs the leaf's start.sh as a program when it is executable,
#      and with sh when it is not. The planted-fault leaves are in scripts/testdata/reviewer-bench (see
#      ygg-reviewer-bench.sh);
#      With --brief-note FILE, the run's brief is the text of FILE, a blank line, then the task's instruction.md
#      (B-109). A note that narrows the implementer's task keeps the work small, and the reviewer still gets the
#      whole spec. A changed brief is another task version, and odin grades a brief only as the instruction.md of
#      a task in grader.tasks_dir whose brief_sha256 it matches. So the task folder is copied to
#      DIR/smoke-real-<time>/tasks/<task>, with that brief as its instruction.md, its SHA-256 as brief_sha256, and
#      a derived version (the patch number plus 1000: 1.0.0 becomes 1.0.1000). Every note gives that same
#      version, so two runs with different notes have the same task_version in score.json and differ only in
#      brief_sha256: never group scores by version alone. The run's brief is that instruction.md and
#      grader.tasks_dir is DIR/smoke-real-<time>/tasks. The lines "the brief note" and "the task is a derived
#      version" say which file was used and the version and hash, in the terminal and in report.txt.
#      FILE must exist and have text. See scripts/testdata/reviewer-bench/P4-note.md;
#   4. prints which ygg runs (path, modified time; for a build from --odin, the odin commit, the tree state and
#      the go.work file the build used, or "no go.work"; GOWORK=off turns go.work off; else the odin commit of its
#      build facts), then
#      runs `ygg doctor` on that config. A config that doctor refuses stops the script before any money is spent;
#   5. with --dry-run, stops here and prints what it would run, and what it would do after the run;
#   6. otherwise runs `ygg run` under `timeout` (--wall, default 90m) with the credentials loaded in a subshell
#      only, and keeps the raw output in DIR/smoke-real-<time>/run.txt (shown live: do not paste that file);
#   7. prints the evidence report (credentials removed) and keeps it in DIR/smoke-real-<time>/report.txt, with
#      the ygg line; then the score; with --from-leaf, whether a finding took the repair path (ygg-repair-path.sh:
#      raised, fixed, closed, or the missing step; also added to report.txt); and the COST read from the ledger.
#      --clip copies the whole report.txt to the Windows clipboard (clip.exe, in WSL).
# The credentials are loaded by `. FILE` in the subshell that runs ygg, as the other smoke scripts do, and nothing
# in this script echoes, greps for a value, or copies them. The exit code is the run's (0 done, 1 a node failed,
# 3 stopped, 4 paused, 5 done with tasks given up, 124 the wall clock ended it) or 2 for a refusal before it.
# Defaults: DIR=$HOME/ygg-it, FILE=$HOME/.config/ouroboric/factory.env. For tests and other machines: YGG_CMD (how
# ygg runs), YGG_ODIN (the odin folder), YGG_BIND (the bind mount, default /mnt/wsl/ygg-bind), YGG_CLI_VERSION
# (default 0.89.0). The engine environment comes from ygg-engine.sh (YGG_ENGINE_CHECK=0 skips it).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=ygg-build-facts.sh
. "$HERE/ygg-build-facts.sh"
any_ygg=0
dir="$HOME/ygg-it" envfile="$HOME/.config/ouroboric/factory.env" tasks="$HERE/../../mimir" wall=90m dry=0 build=0 clip=0
leaf="" implementer="" note="" models=""
odin="${YGG_ODIN:-$HERE/../../yggdrasil/odin}"
usage() { echo "usage: ygg-smoke-real.sh [--dry-run] [--build] [--folder DIR] [--env FILE] [--tasks DIR] [--odin DIR] [--wall TIME] [--clip] [--from-leaf LEAF] [--implementer AGENT:MODEL] [--models FILE] [--brief-note FILE] [--any-ygg]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --build) build=1; shift ;;
    --folder) [ $# -ge 2 ] || usage; dir="$2"; shift 2 ;;
    --env) [ $# -ge 2 ] || usage; envfile="$2"; shift 2 ;;
    --tasks) [ $# -ge 2 ] || usage; tasks="$2"; shift 2 ;;
    --odin) [ $# -ge 2 ] || usage; odin="$2"; shift 2 ;;
    --wall) [ $# -ge 2 ] || usage; wall="$2"; shift 2 ;;
    --clip) clip=1; shift ;;
    --from-leaf) [ $# -ge 2 ] || usage; leaf="$2"; shift 2 ;;
    --implementer) [ $# -ge 2 ] || usage; implementer="$2"; shift 2 ;;
    --models) [ $# -ge 2 ] || usage; models="$2"; shift 2 ;;
    --brief-note) [ $# -ge 2 ] || usage; note="$2"; shift 2 ;;
    --any-ygg) any_ygg=1; shift ;;
    *) usage ;;
  esac
done
fail() { echo "smoke-real: $*" >&2; exit 2; }
task=smoke-notes
bind="${YGG_BIND:-/mnt/wsl/ygg-bind}"
[[ $wall =~ ^[1-9][0-9]*[smh]$ ]] || fail "--wall is a number and s, m or h, such as 90m"
# The implementer goes into a YAML line as it is, so its model has only the characters a model id needs.
if [ -n "$implementer" ]; then
  impl_agent="${implementer%%:*}" impl_model="${implementer#*:}"
  ok=0
  if [[ $implementer == *:* ]] && [[ $impl_model =~ ^[A-Za-z0-9._/:-]+$ ]]; then
    case "$impl_agent" in
      claude-code) ok=1 ;;
      opencode) { [[ $impl_model == openrouter/?* ]] || [[ $impl_model =~ ^local/[a-z0-9][a-z0-9._-]{0,63}$ ]]; } && ok=1 ;;
    esac
  fi
  [ "$ok" = 1 ] || fail "--implementer is AGENT:MODEL, with AGENT claude-code or opencode; an opencode MODEL is openrouter/<model> or local/<name>, such as opencode:openrouter/qwen/qwen3.8-27b"
fi

export PATH="$dir/dc/node_modules/.bin:$PATH"
if [ "${YGG_ENGINE_CHECK:-1}" = 1 ]; then
  engine_env="$("$HERE/ygg-engine.sh" env --folder "$dir")" || exit 2
  eval "$engine_env"
fi
[ -f "$dir/factory.yaml" ] || fail "$dir/factory.yaml is missing; it names the engine (sandbox.engine)"
engine="$(sed -n 's/^[[:space:]]*engine:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$dir/factory.yaml" | head -n 1)"
case "$engine" in unix://*) ;; *) fail "sandbox.engine in $dir/factory.yaml is '${engine:-missing}'; it must be a unix:// URL" ;; esac
for tool in jq python3 git timeout sha256sum; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"; done
tasks="$(cd "$tasks" 2>/dev/null && pwd)" || fail "no mimir folder at $tasks (--tasks)"
odin="$(cd "$odin" 2>/dev/null && pwd)" || fail "no odin folder at $odin (--odin)"
# The stale-binary guard, before anything is made: only a ygg from PATH (YGG_CMD and a build from --odin are not).
if [ -z "${YGG_CMD:-}" ] && command -v ygg >/dev/null 2>&1; then
  ygg_guard smoke-real "$odin" "$any_ygg" "$dry" || exit 2
fi
realm="$odin/testdata/smoke-grade"
public="$tasks/$task/sample-suite"
example="$realm/factory.real.example.yaml"
for f in "$tasks/$task/task.toml" "$tasks/$task/instruction.md" "$public/tests/manifest.json" "$public/tests/test.sh" "$realm/pack.yaml" "$example"; do
  [ -f "$f" ] || fail "$f is missing"
done
suite="$(sed -n 's/^suite[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$tasks/$task/task.toml" | head -n 1)"
[ -n "$suite" ] || fail "$tasks/$task/task.toml has no metadata.suite"

# The brief note: a file with some text in it (not only blanks). The task.toml it derives a version from has one
# version line of the form 1.2.3 and one brief_sha256 line. odin's task.version is 1.2.3 and nothing else
# (gungnir.ValidVersion), so the derived version adds 1000 to the patch number: 1.0.0 becomes 1.0.1000.
if [ -n "$note" ]; then
  [ -f "$note" ] || fail "no brief note at $note (--brief-note)"
  grep -q '[^[:space:]]' "$note" || fail "the brief note $note is empty (--brief-note)"
  note="$(cd "$(dirname "$note")" && pwd)/$(basename "$note")"
  for key in version brief_sha256; do
    n="$(grep -c "^${key}[[:space:]]*=" "$tasks/$task/task.toml" || true)"
    [ "$n" = 1 ] || fail "$tasks/$task/task.toml has $n line(s) that set $key; --brief-note needs exactly 1"
  done
  old_version="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "$tasks/$task/task.toml")"
  [[ $old_version =~ ^([0-9]+\.[0-9]+)\.([0-9]+)$ ]] || fail "the version in $tasks/$task/task.toml is '$old_version'; --brief-note needs one of the form 1.2.3"
  version="${BASH_REMATCH[1]}.$((10#${BASH_REMATCH[2]} + 1000))"
fi

# The leaf to start from: its files, without .git, each a plain name pack.yaml can list without quotes.
if [ -n "$leaf" ]; then
  [ -d "$leaf" ] || fail "no leaf folder at $leaf (--from-leaf)"
  leaf="$(cd "$leaf" && pwd)"
  odd="$(cd "$leaf" && find . -name .git -prune -o ! -type f ! -type d -print | head -n 1)"
  [ -z "$odd" ] || fail "$leaf has $odd, which is neither a file nor a folder; odin's first commit takes plain files only"
  leaf_files="$(cd "$leaf" && find . -name .git -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort)"
  [ -n "$leaf_files" ] || fail "$leaf has no files"
  while IFS= read -r f; do
    [[ $f =~ ^[A-Za-z0-9._/-]+$ ]] || fail "the leaf file '$f' has a name pack.yaml cannot list without quotes"
  done <<<"$leaf_files"
  leaf_files="$(printf '%s\n' "$leaf_files" | paste -sd, - | sed 's/,/, /g')"
  template="$(sed -n 's|^  repos/notes: {.*template: \([^,} ]*\).*|\1|p' "$realm/pack.yaml")"
  [ -n "$template" ] || fail "$realm/pack.yaml has no line for the leaf repos/notes with a template"
fi

# The credentials file: its existence, and the two names. grep -c prints a count and nothing else; the file's
# lines are never shown, stored or compared. A name needs one line, with something after the equals sign.
[ -f "$envfile" ] || fail "the credentials file $envfile is missing"
# The roles the config will have: the example's, with the implementer given. The names and the model list follow.
roles_text="$(sed -n '/^roles:/,/^[^ ]/p' "$example" | grep -E '^  [a-z]+:' || true)"
if [ -n "$implementer" ]; then
  roles_text="$(printf '%s\n' "$roles_text" | grep -v '^  implementer:' || true)"$'\n'"  implementer: { agent: $impl_agent, model: $impl_model }"
fi
need_claude=0 need_router=0 need_local=0
grep -q -E 'agent:[[:space:]]*claude-code' <<<"$roles_text" && need_claude=1
grep -q -E 'model:[[:space:]]*openrouter/' <<<"$roles_text" && need_router=1
grep -q -E 'model:[[:space:]]*local/' <<<"$roles_text" && need_local=1
# The server holds one model at a time (spec 5.2.1): roles on two local models are refused before anything is made.
local_models="$(grep -o -E 'model:[[:space:]]*local/[^ ,}]*' <<<"$roles_text" | sed -E 's/^model:[[:space:]]*//' | sort -u || true)"
[ "$(printf '%s' "$local_models" | grep -c .)" -le 1 ] || fail "roles on two different local models ($(printf '%s' "$local_models" | paste -sd' ')): the local model server holds one; name the same local/<name> for every local role"
if [ "$need_local" -eq 1 ] && [ -z "$models" ]; then fail "a role is on a local model (opencode:local/<name>): --models FILE, the model list, is needed"; fi
if [ "$need_local" -eq 0 ] && [ -n "$models" ]; then fail "--models goes with a role on a local model (opencode:local/<name>); no role is on one"; fi
if [ -n "$models" ]; then
  [ -f "$models" ] || fail "--models $models: no such file"
  models="$(readlink -f -- "$models")"
  [[ $models =~ ^[A-Za-z0-9._/@+-]+$ ]] || fail "--models '$models' has a character outside A-Za-z0-9._/@+- (no spaces); it goes into factory.yaml"
fi
names=()
[ "$need_claude" -eq 0 ] || names+=(CLAUDE_CODE_OAUTH_TOKEN)
[ "$need_router" -eq 0 ] || names+=(OPENROUTER_API_KEY)
for name in ${names[@]+"${names[@]}"}; do
  n="$(grep -c -E "^(export[[:space:]]+)?${name}=[^[:space:]]" "$envfile" || true)"
  [ "$n" = 1 ] || fail "$envfile has $n line(s) that set $name with a value; it needs exactly 1"
done

work="$dir/smoke-real-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$work/suites/$task/$suite" "$work/project"
cp -r "$public/tests" "$work/suites/$task/$suite/tests"
project="$work/project"
git -C "$project" init -q -b main
printf 'root: true\nowner: ouroboric-dev\nvisibility: private\n' >"$project/umbrella.yaml"
# The grader's /app is the project. The product is built in the leaf; this file starts it.
# odin writes a leaf's first-commit files without the execute bit, so a run from a leaf runs its start.sh with sh
# unless the implementer made it executable. sh is dash in the grader's image, so the shebang wins when it can.
starter=./start.sh
[ -z "$leaf" ] || starter="if [ -x ./start.sh ]; then exec ./start.sh; else exec sh ./start.sh; fi"
# shellcheck disable=SC2016
if [ -z "$leaf" ]; then
  printf '#!/bin/sh\ncd "$(dirname "$0")/repos/notes" && exec %s\n' "$starter" >"$project/start.sh"
else
  printf '#!/bin/sh\ncd "$(dirname "$0")/repos/notes" || exit 1\n%s\n' "$starter" >"$project/start.sh"
fi
chmod +x "$project/start.sh"
git -C "$project" add umbrella.yaml start.sh
git -C "$project" -c user.name=ygg -c user.email=ygg@example.invalid commit -q -m "the real-agent smoke project"
echo "smoke-real: made $work"
brief="$tasks/$task/instruction.md" note_line="" derived_line="" grader_tasks="$tasks"
if [ -n "$note" ]; then
  # A changed brief is another task version (task.toml: "Any change to the brief makes a new task version"), and
  # odin grades a brief only against the task it is the instruction.md of. So the run gets its own copy of the
  # task, with the noted brief, its hash and the derived version, and the grader reads its tasks from there.
  derived="$work/tasks/$task" toml="$work/tasks/$task/task.toml"
  mkdir -p "$work/tasks"
  cp -R "$tasks/$task" "$derived"
  { printf '%s\n\n' "$(<"$note")"; cat "$tasks/$task/instruction.md"; } >"$derived/instruction.md"
  brief_sha="$(sha256sum "$derived/instruction.md" | cut -d' ' -f1)"
  sed -i -e "s/^version[[:space:]]*=.*/version = \"$version\"/" -e "s/^brief_sha256[[:space:]]*=.*/brief_sha256 = \"$brief_sha\"/" "$toml"
  { printf '# A derived version of %s %s, made by ygg-smoke-real.sh --brief-note: its instruction.md is the note\n' "$task" "$old_version"
    printf '# %s, a blank line, then the task'"'"'s instruction.md. The version and brief_sha256 below are the derived ones.\n' "$note"
    cat "$toml"; } >"$toml.new"
  mv "$toml.new" "$toml"
  if ! grep -q -x -F "version = \"$version\"" "$toml" || ! grep -q -x -F "brief_sha256 = \"$brief_sha\"" "$toml"; then
    fail "the version and brief_sha256 could not be set in $toml"
  fi
  brief="$derived/instruction.md" grader_tasks="$work/tasks"
  note_line="smoke-real: the brief note: $note (the brief is $brief: the note, a blank line, then the task's instruction.md)"
  derived_line="smoke-real: the task is a derived version: $task $version (from $old_version), brief_sha256 $brief_sha, in $derived; grader.tasks_dir is $grader_tasks"
  echo "$note_line"
  echo "$derived_line"
fi
echo "smoke-real: the suite is the PUBLIC sample suite $public/tests (suite $suite)"
if [ -n "$leaf" ]; then
  # The run's own copy of the pack, with LEAF as the template of repos/notes. odin's pack is not changed.
  mkdir -p "$work/pack/$template"
  tar -C "$realm" --exclude="./$template" -cf - . | tar -C "$work/pack" -xf -
  tar -C "$leaf" --exclude=.git -cf - . | tar -C "$work/pack/$template" -xf -
  sed -i "/^  repos\/notes: {/ s|first_commit: \[[^]]*\]|first_commit: [$leaf_files]|" "$work/pack/pack.yaml"
  grep -q -F "first_commit: [$leaf_files]" "$work/pack/pack.yaml" || fail "the first commit of repos/notes could not be set in $work/pack/pack.yaml"
  realm="$work/pack"
  echo "smoke-real: the leaf repos/notes starts from $leaf: $realm is odin's pack with that leaf as its template, and every file in the first commit"
fi

# The config: the example with its places filled. Its caps are the example's.
text="$(<"$example")"
text="${text//@ENGINE@/$engine}"
text="${text//@FOLDER@/$dir}"
text="${text//@BIND@/$bind}"
text="${text//@TASKS@/$grader_tasks}"
text="${text//@SUITES@/$work/suites}"
if [ "$need_router" -eq 0 ]; then
  # No role is paid per token: the dollar caps stay out of the config.
  text="$(sed -E '/^  per_(run|day):/ s/,[[:space:]]*usd:[[:space:]]*[0-9.]+//' <<<"$text")"
fi
if [ "$need_local" -eq 1 ]; then text+=$'\nmodels:\n'"  file: $models"; fi
printf '%s\n' "$text" >"$work/factory.yaml"
if grep -q '@[A-Z]*@' "$work/factory.yaml"; then fail "$work/factory.yaml still has a place to fill: $(grep -o '@[A-Z]*@' "$work/factory.yaml" | sort -u | tr '\n' ' ')"; fi
if [ -n "$implementer" ]; then
  n="$(grep -c '^  implementer:' "$work/factory.yaml" || true)"
  [ "$n" = 1 ] || fail "$example has $n implementer line(s) under roles; --implementer needs exactly 1"
  sed -i "s|^  implementer:.*|  implementer: { agent: $impl_agent, model: $impl_model } # set by ygg-smoke-real.sh --implementer|" "$work/factory.yaml"
fi
echo "smoke-real: the implementer: $(sed -n 's/^  implementer:[[:space:]]*\({[^}]*}\).*/\1/p' "$work/factory.yaml")"

# Which ygg runs. `ygg` has no version command, so the line gives the path and the modified time of the binary;
# for a build from --odin it also gives the odin commit and whether that tree is dirty. YGG_CMD and a ygg on PATH
# are run as they are: the line is what shows a stale one.
ygg="${YGG_CMD:-}" built=0
if [ -z "$ygg" ]; then
  if command -v ygg >/dev/null 2>&1; then ygg=ygg
  else
    mkdir -p "$work/bin"
    (cd "$odin" && go build -o "$work/bin/ygg" ./cmd/ygg) || fail "go build of ygg failed in $odin"
    ygg="'$work/bin/ygg'" built=1
  fi
fi
first="${ygg%% *}"
if [ "$built" -eq 1 ]; then first="$work/bin/ygg"; fi
bin="$(command -v -- "$first" 2>/dev/null || true)"
if [ -n "$bin" ]; then
  stamp="$(date -r "$bin" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"
  ygg_line="smoke-real: ygg: $bin, modified $stamp"
else
  ygg_line="smoke-real: ygg: $first (not found on PATH)"
fi
if [ "$built" -eq 1 ]; then
  sha="$(git -C "$odin" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  if [ -n "$(git -C "$odin" status --porcelain 2>/dev/null)" ]; then tree="tree DIRTY"; else tree="tree clean"; fi
  # The same environment as the build, so GOWORK=off is honoured. go prints a path, nothing, or "off".
  gw="$(cd "$odin" && go env GOWORK 2>/dev/null || true)"
  case "$gw" in ""|off) gw="no go.work" ;; esac
  ygg_line="$ygg_line, built from $odin at commit $sha, $tree, go.work: $gw"
elif [ -n "$bin" ] && facts_odin="$(ygg_facts_get "$(readlink -f -- "$bin")" odin)"; then
  ygg_line="$ygg_line, built from odin $facts_odin (build facts)"
else
  ygg_line="$ygg_line, odin commit unknown (not built by this script)"
fi
echo "$ygg_line"

echo "smoke-real: the caps in $work/factory.yaml:"
{ grep -E '^  per_(run|day):' "$work/factory.yaml" || true; } | sed 's/^/  /'
echo "smoke-real: ygg doctor on that config"
if ! eval "$ygg doctor --project '$project' --config '$work/factory.yaml'"; then fail "ygg doctor refused the config; nothing was spent"; fi

# What happens after the run. The dry run prints it from the same settings, since only a real run reaches it.
after_run_notes() {
  if [ -n "$leaf" ]; then echo "smoke-real: after the run: ygg-repair-path.sh checks the repair path in the run's ledger (--from-leaf)"; fi
  if [ "$clip" -eq 1 ]; then
    if command -v clip.exe >/dev/null 2>&1; then echo "smoke-real: after the run: report.txt is copied to the clipboard with clip.exe"
    else echo "smoke-real: --clip needs clip.exe (WSL); the report will be in report.txt only"; fi
  fi
}

run="$ygg run --project '$project' --config '$work/factory.yaml' --graph '$realm' --brief '$brief'"
if [ "$dry" -eq 1 ]; then
  [ "$build" -eq 0 ] || echo "smoke-real: would run: $ygg sandbox build --config '$work/factory.yaml' --realm '$realm'"
  echo "smoke-real: would run: timeout --signal=INT --kill-after=2m $wall $run"
  after_run_notes
  echo "smoke-real: dry run: nothing was started and the credentials were not loaded"
  exit 0
fi

out="$work/run.txt"
# The credentials live only in this subshell; nothing here prints them.
set +e
(
  { set +x; } 2>/dev/null # no trace of the sourced assignments, even under bash -x or SHELLOPTS=xtrace
  set -a
  # shellcheck source=/dev/null
  . "$envfile"
  set +a
  if [ "$build" -eq 1 ]; then eval "$ygg sandbox build --config '$work/factory.yaml' --realm '$realm'"; fi
  eval "timeout --signal=INT --kill-after=2m '$wall' $run"
) 2>&1 | tee "$out"
rc="${PIPESTATUS[0]}"
set -e
echo "smoke-real: the run ended with exit code $rc (0 done, 1 a node failed, 3 stopped, 4 paused, 5 done with tasks given up, 124 wall clock)" >&2

report="$work/report.txt"
( { set +x; } 2>/dev/null # as above
  echo "$ygg_line"
  if [ -n "$note_line" ]; then echo "$note_line"; echo "$derived_line"; fi
  set -a
  # shellcheck source=/dev/null
  . "$envfile"
  set +a
  YGG_CMD="$ygg" "$HERE/ygg-evidence.sh" --config "$work/factory.yaml" --output "$out" "$project"
) | tee "$report" || echo "smoke-real: no evidence report: the run left no ledger" >&2

# The score and the cost come from the run folder and its ledger; neither holds a credential.
id="$(find "$project/.factory/runs" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n 1 || true)"
if [ -n "$id" ] && [ -f "$project/.factory/runs/$id/score.json" ]; then
  jq -r '"smoke-real: score \(.task) \(.task_version): reward \(.reward), fail-to-pass \(.fail_to_pass.passed)/\(.fail_to_pass.total), pass-to-pass \(.pass_to_pass.passed)/\(.pass_to_pass.total)"' "$project/.factory/runs/$id/score.json"
else
  echo "smoke-real: no score.json: the run did not reach the grade node"
fi
if [ -n "$id" ] && [ -f "$project/.factory/runs/$id/ledger.jsonl" ]; then
  # Only a run from a planted-fault leaf is meant to take the repair path; on any other run the line would read as a failure.
  if [ -n "$leaf" ]; then "$HERE/ygg-repair-path.sh" "$project/.factory/runs/$id/ledger.jsonl" | tee -a "$report" || true; fi
  "$HERE/ygg-cost.sh" "$project/.factory/runs/$id/ledger.jsonl" "$work/factory.yaml" || echo "smoke-real: the cost could not be read from the ledger" >&2
fi
# The whole report.txt (the ygg line, the redacted evidence, the repair path) is what the founder pastes.
if [ "$clip" -eq 1 ]; then
  if command -v clip.exe >/dev/null 2>&1 && [ -f "$report" ]; then clip.exe <"$report"; echo "(report.txt copied to the clipboard)" >&2
  else echo "smoke-real: --clip needs clip.exe (WSL); the report is in $report" >&2; fi
fi
echo "smoke-real: the folder is $work" >&2
exit "$rc"

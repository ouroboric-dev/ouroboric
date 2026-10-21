#!/usr/bin/env bash
# Run the real-agent smoke (v0-H17): the task smoke-notes built by the real Claude Code and the real OpenCode on
# OpenRouter, then graded. IT COSTS MONEY: the caps are in odin/testdata/smoke-grade/factory.real.example.yaml.
#   ygg-smoke-real.sh [--dry-run] [--build] [--folder DIR] [--env FILE] [--tasks DIR] [--odin DIR] [--wall TIME] [--clip]
#                     [--from-leaf LEAF] [--implementer AGENT:MODEL]
# The suite is the PUBLIC sample suite of the task (no hidden suite of smoke-notes exists); the agents never mount
# it. Needs DIR/factory.yaml (it names the engine; this script never writes it), the credentials file, the
# devcontainer CLI 0.89.0, jq and python3, the engine up, the bind mount present, and a checkout of `mimir`. It
#   1. checks the engine, the tools and the task;
#   2. checks the credentials file WITHOUT reading it: the file exists, and each of the two names
#      CLAUDE_CODE_OAUTH_TOKEN and OPENROUTER_API_KEY is on one line with a value after it (grep -c counts the
#      lines; no value is printed or kept);
#   3. makes DIR/smoke-real-<time> with the project, the public suite and the factory.yaml filled from the
#      example (its caps are the real ones). With --implementer AGENT:MODEL, its implementer line is replaced
#      (AGENT is claude-code or opencode; an opencode MODEL is openrouter/<model>), so one role changes (B-110).
#      With --from-leaf LEAF, the leaf repos/notes starts from the files of LEAF (without .git) instead of the
#      pack's template (B-109): the pack is copied to DIR/smoke-real-<time>/pack, LEAF becomes the copy's
#      template, and every file of LEAF goes in the leaf's first commit. odin writes those files without the
#      execute bit, so the project's start.sh then runs the leaf's start.sh with sh. The planted-fault leaves are
#      in scripts/testdata/reviewer-bench (see ygg-reviewer-bench.sh);
#   4. prints which ygg runs (path, modified time; for a build from --odin, the odin commit and tree state), then
#      runs `ygg doctor` on that config. A config that doctor refuses stops the script before any money is spent;
#   5. with --dry-run, stops here and prints what it would run;
#   6. otherwise runs `ygg run` under `timeout` (--wall, default 90m) with the credentials loaded in a subshell
#      only, and keeps the raw output in DIR/smoke-real-<time>/run.txt (shown live: do not paste that file);
#   7. prints the evidence report (credentials removed), the score, whether a finding took the repair path
#      (ygg-repair-path.sh: raised, fixed, closed, or the missing step), and the COST read from the ledger.
# The credentials are loaded by `. FILE` in the subshell that runs ygg, as the other smoke scripts do, and nothing
# in this script echoes, greps for a value, or copies them. The exit code is the run's (0 done, 1 a node failed,
# 3 stopped, 4 paused, 5 done with tasks given up, 124 the wall clock ended it) or 2 for a refusal before it.
# Defaults: DIR=$HOME/ygg-it, FILE=$HOME/.config/ouroboric/factory.env. For tests and other machines: YGG_CMD (how
# ygg runs), YGG_ODIN (the odin folder), YGG_BIND (the bind mount, default /mnt/wsl/ygg-bind), YGG_CLI_VERSION
# (default 0.89.0). The engine environment comes from ygg-engine.sh (YGG_ENGINE_CHECK=0 skips it).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="$HOME/ygg-it" envfile="$HOME/.config/ouroboric/factory.env" tasks="$HERE/../../mimir" wall=90m dry=0 build=0 clip=()
leaf="" implementer=""
odin="${YGG_ODIN:-$HERE/../../yggdrasil/odin}"
usage() { echo "usage: ygg-smoke-real.sh [--dry-run] [--build] [--folder DIR] [--env FILE] [--tasks DIR] [--odin DIR] [--wall TIME] [--clip] [--from-leaf LEAF] [--implementer AGENT:MODEL]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --build) build=1; shift ;;
    --folder) [ $# -ge 2 ] || usage; dir="$2"; shift 2 ;;
    --env) [ $# -ge 2 ] || usage; envfile="$2"; shift 2 ;;
    --tasks) [ $# -ge 2 ] || usage; tasks="$2"; shift 2 ;;
    --odin) [ $# -ge 2 ] || usage; odin="$2"; shift 2 ;;
    --wall) [ $# -ge 2 ] || usage; wall="$2"; shift 2 ;;
    --clip) clip=(--clip); shift ;;
    --from-leaf) [ $# -ge 2 ] || usage; leaf="$2"; shift 2 ;;
    --implementer) [ $# -ge 2 ] || usage; implementer="$2"; shift 2 ;;
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
      opencode) [[ $impl_model == openrouter/?* ]] && ok=1 ;;
    esac
  fi
  [ "$ok" = 1 ] || fail "--implementer is AGENT:MODEL, with AGENT claude-code or opencode; an opencode MODEL is openrouter/<model>, such as opencode:openrouter/qwen/qwen3.8-27b"
fi

export PATH="$dir/dc/node_modules/.bin:$PATH"
if [ "${YGG_ENGINE_CHECK:-1}" = 1 ]; then
  engine_env="$("$HERE/ygg-engine.sh" env --folder "$dir")" || exit 2
  eval "$engine_env"
fi
[ -f "$dir/factory.yaml" ] || fail "$dir/factory.yaml is missing; it names the engine (sandbox.engine)"
engine="$(sed -n 's/^[[:space:]]*engine:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$dir/factory.yaml" | head -n 1)"
case "$engine" in unix://*) ;; *) fail "sandbox.engine in $dir/factory.yaml is '${engine:-missing}'; it must be a unix:// URL" ;; esac
for tool in jq python3 git timeout; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"; done
tasks="$(cd "$tasks" 2>/dev/null && pwd)" || fail "no mimir folder at $tasks (--tasks)"
odin="$(cd "$odin" 2>/dev/null && pwd)" || fail "no odin folder at $odin (--odin)"
realm="$odin/testdata/smoke-grade"
public="$tasks/$task/sample-suite"
example="$realm/factory.real.example.yaml"
for f in "$tasks/$task/task.toml" "$tasks/$task/instruction.md" "$public/tests/manifest.json" "$public/tests/test.sh" "$realm/pack.yaml" "$example"; do
  [ -f "$f" ] || fail "$f is missing"
done
suite="$(sed -n 's/^suite[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$tasks/$task/task.toml" | head -n 1)"
[ -n "$suite" ] || fail "$tasks/$task/task.toml has no metadata.suite"

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
for name in CLAUDE_CODE_OAUTH_TOKEN OPENROUTER_API_KEY; do
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
# odin writes a leaf's first-commit files without the execute bit, so a run from a leaf runs its start.sh with sh.
starter=./start.sh
[ -z "$leaf" ] || starter="sh ./start.sh"
# shellcheck disable=SC2016
printf '#!/bin/sh\ncd "$(dirname "$0")/repos/notes" && exec %s\n' "$starter" >"$project/start.sh"
chmod +x "$project/start.sh"
git -C "$project" add umbrella.yaml start.sh
git -C "$project" -c user.name=ygg -c user.email=ygg@example.invalid commit -q -m "the real-agent smoke project"
echo "smoke-real: made $work"
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
text="${text//@TASKS@/$tasks}"
text="${text//@SUITES@/$work/suites}"
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
  ygg_line="$ygg_line, built from $odin at commit $sha, $tree"
else
  ygg_line="$ygg_line, odin commit unknown (not built by this script)"
fi
echo "$ygg_line"

echo "smoke-real: the caps in $work/factory.yaml:"
{ grep -E '^  per_(run|day):' "$work/factory.yaml" || true; } | sed 's/^/  /'
echo "smoke-real: ygg doctor on that config"
if ! eval "$ygg doctor --project '$project' --config '$work/factory.yaml'"; then fail "ygg doctor refused the config; nothing was spent"; fi

run="$ygg run --project '$project' --config '$work/factory.yaml' --graph '$realm' --brief '$tasks/$task/instruction.md'"
if [ "$dry" -eq 1 ]; then
  [ "$build" -eq 0 ] || echo "smoke-real: would run: $ygg sandbox build --config '$work/factory.yaml' --realm '$realm'"
  echo "smoke-real: would run: timeout --signal=INT --kill-after=2m $wall $run"
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
  set -a
  # shellcheck source=/dev/null
  . "$envfile"
  set +a
  YGG_CMD="$ygg" "$HERE/ygg-evidence.sh" --config "$work/factory.yaml" --output "$out" ${clip[@]+"${clip[@]}"} "$project"
) | tee "$report" || echo "smoke-real: no evidence report: the run left no ledger" >&2

# The score and the cost come from the run folder and its ledger; neither holds a credential.
id="$(find "$project/.factory/runs" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n 1 || true)"
if [ -n "$id" ] && [ -f "$project/.factory/runs/$id/score.json" ]; then
  jq -r '"smoke-real: score \(.task) \(.task_version): reward \(.reward), fail-to-pass \(.fail_to_pass.passed)/\(.fail_to_pass.total), pass-to-pass \(.pass_to_pass.passed)/\(.pass_to_pass.total)"' "$project/.factory/runs/$id/score.json"
else
  echo "smoke-real: no score.json: the run did not reach the grade node"
fi
if [ -n "$id" ] && [ -f "$project/.factory/runs/$id/ledger.jsonl" ]; then
  "$HERE/ygg-repair-path.sh" "$project/.factory/runs/$id/ledger.jsonl" | tee -a "$report" || true
  "$HERE/ygg-cost.sh" "$project/.factory/runs/$id/ledger.jsonl" "$work/factory.yaml" || echo "smoke-real: the cost could not be read from the ledger" >&2
fi
echo "smoke-real: the folder is $work" >&2
exit "$rc"

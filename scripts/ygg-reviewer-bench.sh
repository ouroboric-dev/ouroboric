#!/usr/bin/env bash
# Compare reviewer models on a leaf with a known planted fault (B-108; docs/6-journal/2026-10-20-choosing-the-
# reviewer-model.md). IT COSTS MONEY unless --dry-run: each session is one OpenCode session on OpenRouter (a paid
# API: OPENROUTER_API_KEY), about 1 cent for qwen/qwen3.8-27b.
#   ygg-reviewer-bench.sh --model MODEL --leaf DIR --sessions N [--fault REGEX] [--effort low|medium|high|off]
#                         [--out OUT] [--odin DIR] [--tasks DIR] [--gleipnir DIR] [--opencode BIN] [--any-opencode]
#                         [--dry-run]
# Each session reviews a fresh copy of the leaf (one git commit, no .git of the original) with the prompt the
# engine gives the smoke's reviewer:
#   1. odin's smoke pack reviewer prompt, testdata/smoke-grade/prompts/review.md (odin PRs #21 and #22);
#   2. "## Brief" and the brief of the task, mimir smoke-notes/instruction.md;
#   3. the engine's answer request: jormungandr prompt.go, ReviewRequest and ReportFormat (as of jormungandr
#      ec8f18c), for the reviewer id "review" and the passed check "unit".
# The settings are those of the OpenCode adapter (gleipnir opencode/opencode.go): strict privacy on OpenRouter (no
# data kept, zero retention, no fallback), the effort named on every request (high), read-only permissions, 10
# turns (the graph's max_turns) and 5 minutes. There is no token limit: gleipnir ends a session at the node's
# max_tokens, and the bench has only the 300-second timeout. OpenCode runs with no project or Claude Code
# config, and no update, share or model fetch.
# The OpenCode is the engine's: the version gleipnir pins (sandbox/images.go in --gleipnir DIR, default the
# sibling checkout). Without --opencode BIN it is installed once with npm into
# ${XDG_CACHE_HOME:-$HOME/.cache}/ouroboric/opencode/VERSION (linux x64 only; --dry-run installs nothing). The
# bench runs BIN --version and refuses a version other than the pin, unless --any-opencode is given. The argv is
# the engine's for a read-only session, run --format json -m openrouter/MODEL; --standalone, which OpenCode 2
# and later have and 1.x lacks, is added only when the major version is 2 or more. The terminal output and
# summary.md name the binary and its version. As in the engine, a session gets
# only the variables the script names (env -i): PATH, HOME, TMPDIR, XDG_CACHE_HOME (if set), OPENROUTER_API_KEY
# and the OpenCode settings. No OPENCODE_* variable and no Anthropic credential of the caller reaches it. Each
# session has its own empty XDG_CONFIG_HOME and XDG_DATA_HOME, in a folder under TMPDIR, outside HOME, so no
# global OpenCode config applies. The cache (models catalogue, provider package) is the host's.
# It prints for each session whether the answer is a valid report, by the engine's rules (gungnir ParseReport:
# prose before the report is ignored, nothing may follow it; and jormungandr Review on a first review), and the
# claims of its findings; then the journal's table. A finding is the fault when REGEX (Python, case ignored)
# matches its claim or location: read the claims as well. "Tokens in" counts cache reads, "(new)" does not;
# "Tokens out" includes reasoning. The cost is OpenCode's own figure. A session with tokens and cost 0 (OpenRouter
# reports no cost for the Claude models) makes the cost "unknown".
# OUT (new or empty; default a new folder under TMPDIR) keeps prompt.md, session-N.jsonl (the events),
# session-N.err, session-N.exit (the exit code) and summary.md. The scorer is ygg-reviewer-bench.py.
# The leaves in scripts/testdata/reviewer-bench, and their --fault:
#   P0  no known fault: the product the failed smoke run built      (no --fault)
#   P1  start.sh runs servr.js                                       'servr'
#   P2  the server listens on 8080, not 3000                         '8080'
#   P3  GET /api/notes returns the oldest first                      'oldest|newest|revers|insertion order'
#   P4  DELETE /api/notes/ID deletes another person's note. server.js reaches notes through notes.of(email);
#       remove in notes.js ignores the owner. Neither file alone shows it.
#       'owner|another (user|person|account)|other (users?|person|people|accounts?)|any (user|person)|not theirs|not the caller|idor'
# The test's fakes: YGG_REVIEWER_BENCH_NPM (the installer command) and YGG_REVIEWER_BENCH_UNAME (the platform).
# Exit 0, or 2 for a refusal.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() {
  echo "usage: ygg-reviewer-bench.sh --model MODEL --leaf DIR --sessions N [--fault REGEX] [--effort low|medium|high|off] [--out OUT] [--odin DIR] [--tasks DIR] [--gleipnir DIR] [--opencode BIN] [--any-opencode] [--dry-run]" >&2
  exit 2
}
fail() { echo "reviewer-bench: $*" >&2; exit 2; }
model="" leaf="" sessions="" fault="" effort=high out="" dry=0 bin="" any=0
odin="$HERE/../../yggdrasil/odin" tasks="$HERE/../../mimir" gleipnir="$HERE/../../yggdrasil/gleipnir"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --any-opencode) any=1; shift ;;
    --opencode) [ $# -ge 2 ] || usage; bin="$2"; shift 2 ;;
    --gleipnir) [ $# -ge 2 ] || usage; gleipnir="$2"; shift 2 ;;
    --model) [ $# -ge 2 ] || usage; model="$2"; shift 2 ;;
    --leaf) [ $# -ge 2 ] || usage; leaf="$2"; shift 2 ;;
    --sessions) [ $# -ge 2 ] || usage; sessions="$2"; shift 2 ;;
    --fault) [ $# -ge 2 ] || usage; fault="$2"; shift 2 ;;
    --effort) [ $# -ge 2 ] || usage; effort="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; out="$2"; shift 2 ;;
    --odin) [ $# -ge 2 ] || usage; odin="$2"; shift 2 ;;
    --tasks) [ $# -ge 2 ] || usage; tasks="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$model" ] && [ -n "$leaf" ] && [ -n "$sessions" ] || usage
[[ $sessions =~ ^[1-9][0-9]*$ ]] || fail "--sessions is a whole number above 0, not '$sessions'"
id="${model#openrouter/}"
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || fail "--model '$model' is not an OpenRouter model id, such as qwen/qwen3.8-27b"
case "$effort" in low | medium | high | off) ;; *) fail "--effort is low, medium, high or off, not '$effort'" ;; esac
for tool in python3 git tar timeout; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"; done
[ -d "$leaf" ] || fail "no leaf folder at $leaf (--leaf)"
leaf="$(cd "$leaf" && pwd)"
if [ -n "$fault" ] && ! python3 -I -c 'import re, sys; re.compile(sys.argv[1])' "$fault" 2>/dev/null; then
  fail "--fault '$fault' is not a Python regular expression"
fi
review="$odin/testdata/smoke-grade/prompts/review.md"
brief="$tasks/smoke-notes/instruction.md"
[ -f "$review" ] || fail "$review is missing (--odin): it is the smoke reviewer's prompt"
[ -f "$brief" ] || fail "$brief is missing (--tasks): it is the brief of the task"

# The OpenCode: the version the engine's sandbox pins (gleipnir sandbox/images.go, OpenCode = "X").
images="$gleipnir/sandbox/images.go"
[ -f "$images" ] || fail "$images is missing (--gleipnir): it names the OpenCode version the engine pins"
pin="$(sed -n 's/^[[:space:]]*OpenCode[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$images" | head -n 1)"
[[ $pin =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "no OpenCode version like 1.18.32 in $images"
installed=1
if [ -z "$bin" ]; then
  platform="$(echo "${YGG_REVIEWER_BENCH_UNAME:-$(uname -sm)}" | tr '[:upper:]' '[:lower:]')"
  [ "$platform" = "linux x86_64" ] || fail "the pinned OpenCode is installed for linux x64 only, not '$platform'; give a binary with --opencode"
  prefix="${XDG_CACHE_HOME:-$HOME/.cache}/ouroboric/opencode/$pin"
  bin="$prefix/node_modules/opencode-linux-x64/bin/opencode"
  if [ ! -x "$bin" ]; then
    installed=0
    if [ "$dry" = 0 ]; then
      mkdir -p "$prefix"
      echo "Installing opencode-ai@$pin into $prefix" >&2
      "${YGG_REVIEWER_BENCH_NPM:-npm}" install --ignore-scripts --prefix "$prefix" "opencode-ai@$pin" >&2 \
        || fail "npm install opencode-ai@$pin failed"
      [ -x "$bin" ] || fail "npm installed opencode-ai@$pin but $bin is missing"
    fi
  fi
fi
if [ "$installed" = 0 ] && [ "$dry" = 1 ]; then
  version="$pin"
  opencode_line="OpenCode: $bin (not installed: a real run would install opencode-ai@$pin with npm; assumed $pin)"
else
  version="$(env -i "PATH=$PATH" "HOME=$HOME" "$bin" --version 2>/dev/null | head -n 1)" || true
  [ -n "$version" ] || fail "'$bin --version' printed nothing"
  v="${version#v}"
  if [ "$v" != "$pin" ]; then
    [ "$any" = 1 ] || fail "$bin is OpenCode $version, not the engine's pin $pin (gleipnir sandbox/images.go); use --any-opencode to measure it anyway"
    opencode_line="OpenCode: $bin $version (not the pin $pin: --any-opencode)"
  else
    opencode_line="OpenCode: $bin $version"
  fi
fi
major="${version#v}"; major="${major%%.*}"
[[ $major =~ ^[0-9]+$ ]] || fail "cannot read a version from '$version'"

[ "$dry" = 1 ] || [ -n "${OPENROUTER_API_KEY:-}" ] || fail "OPENROUTER_API_KEY is not set; use a dedicated OpenRouter key with a credit limit"
if [ -z "$out" ]; then
  out="$(mktemp -d "${TMPDIR:-/tmp}/ygg-reviewer-bench.XXXXXX")"
elif [ -d "$out" ] && [ -n "$(ls -A "$out")" ]; then
  fail "--out $out is not empty; give a new folder"
fi
mkdir -p "$out"
out="$(cd "$out" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ygg-reviewer-bench-work.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

# The prompt, as the engine builds it (odin internal/engine/loop.go, Review): the reviewer's prompt file, the
# brief, then jormungandr.ReviewRequest("review", no open findings, passed ["unit"]).
{
  cat "$review"
  printf '\n\n## Brief\n\n'
  cat "$brief"
  printf '\n\n'
  cat <<'EOF'
## Your answer

Your id is review. Use it as the "source" of every finding.

Answer with one JSON document: end your answer with the document; nothing after it. Any text before it is ignored. The document, bare or in one code fence:

{"findings": [ {"id": "...", "source": "<your id>", "severity": "blocker|major|minor", "location": "path/to/file:LINE", "claim": "what is wrong", "status": "open"} ]}

- "id" names the problem and stays the same every time you report it.
- "location" is a file and a line, or a range such as path/to/file:10-20.
- "status" is "open" for a problem you still see. Say "fixed" only for a problem listed below that you checked
  is gone, and then add "proof": the file:line you read, and the name of one of the checks listed below
  that passed. A finding without both is refused.
- A blocker or major finding of yours that the implementer disputed and a check settled is closed ("overruled"):
  it is not in the list below. Report it again only with proof: a failing check, or a different location than
  before. A repeat with neither is ignored.
- If you find nothing, answer {"findings": []}.

The checks that passed on this work: unit.

The implementer may dispute one of your findings. A dispute is settled by a check: if it holds, the finding is overruled and closed. If you see the same problem again, report it with proof: a failing check, or a different location than the overruled finding. A repeat with neither is ignored.

EOF
} >"$out/prompt.md"

# The session's config, as gleipnir's ConfigJSON makes it for a read-only reviewer under privacy: strict.
reasoning=""
[ "$effort" = off ] || reasoning="\"reasoning\":{\"effort\":\"$effort\"},"
# shellcheck disable=SC2016 # "$schema" is a JSON key, not a variable
conf="$(printf '{"$schema":"https://opencode.ai/config.json","autoupdate":false,"share":"disabled","provider":{"openrouter":{"options":{"apiKey":"{env:OPENROUTER_API_KEY}"},"models":{"%s":{"options":{%s"provider":{"data_collection":"deny","zdr":true,"allow_fallbacks":false}}}}}},"small_model":"openrouter/%s","agent":{"build":{"steps":10}},"permission":{"edit":"deny","bash":"deny","webfetch":"deny","external_directory":"deny","task":"deny","question":"deny"}}' \
  "$id" "$reasoning" "$id")"
# As in the engine, a session gets only the variables named here (env -i): no OPENCODE_* and nothing else of the
# caller's shell. The key is added in the real run only, so the dry run never prints it.
env_args=("PATH=$PATH" "HOME=$HOME")
[ -z "${TMPDIR:-}" ] || env_args+=("TMPDIR=$TMPDIR")
[ -z "${XDG_CACHE_HOME:-}" ] || env_args+=("XDG_CACHE_HOME=$XDG_CACHE_HOME")
env_args+=("OPENCODE_CONFIG_CONTENT=$conf" OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_CLAUDE_CODE=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1
  OPENCODE_DISABLE_AUTOUPDATE=true OPENCODE_DISABLE_SHARE=true OPENCODE_DISABLE_MODELS_FETCH=true)
# The engine's argv for a read-only session (gleipnir opencode/opencode.go); --standalone only where it exists.
cmd=(run)
[ "$major" -lt 2 ] || cmd+=(--standalone)
cmd+=(--format json -m "openrouter/$id")

if [ "$dry" = 1 ]; then
  q() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
  echo "$opencode_line"
  echo "Dry run: it spends nothing. Each of the $sessions sessions would copy $leaf (without .git) to"
  echo "$work/leaf-N, commit it there, and run in that folder:"
  printf '  env -i'
  for a in "${env_args[@]}"; do printf ' %s=%s' "${a%%=*}" "$(q "${a#*=}")"; done
  # shellcheck disable=SC2016 # the key is shown as a reference, never as its value
  printf ' OPENROUTER_API_KEY="$OPENROUTER_API_KEY"'
  printf ' XDG_DATA_HOME=%s XDG_CONFIG_HOME=%s timeout 300 %s %s < %s\n' "$(q "$work/data-N")" "$(q "$work/config-N")" \
    "$(q "$bin")" "${cmd[*]}" "$(q "$out/prompt.md")"
  echo "The prompt is in $out/prompt.md."
  exit 0
fi

for i in $(seq 1 "$sessions"); do
  copy="$work/leaf-$i"
  mkdir -p "$copy" "$work/data-$i" "$work/config-$i"
  tar -C "$leaf" --exclude=.git -cf - . | tar -C "$copy" -xf -
  git -C "$copy" init -q
  git -C "$copy" add -A
  git -C "$copy" -c user.name=reviewer-bench -c user.email=reviewer-bench@localhost -c commit.gpgsign=false \
    commit -q --no-verify -m "The leaf under review"
  echo "session $i of $sessions" >&2
  rc=0
  (cd "$copy" && env -i "${env_args[@]}" OPENROUTER_API_KEY="$OPENROUTER_API_KEY" XDG_DATA_HOME="$work/data-$i" \
    XDG_CONFIG_HOME="$work/config-$i" timeout 300 "$bin" "${cmd[@]}") \
    <"$out/prompt.md" >"$out/session-$i.jsonl" 2>"$out/session-$i.err" || rc=$?
  echo "$rc" >"$out/session-$i.exit"
done

{
  echo "$opencode_line"
  echo
  python3 -I "$HERE/ygg-reviewer-bench.py" "$out" "$sessions" "$fault" "$(basename "$leaf")" "$id"
} | tee "$out/summary.md"
echo "The prompt, the events of each session and this summary are in $out."

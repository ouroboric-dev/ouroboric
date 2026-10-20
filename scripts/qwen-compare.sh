#!/usr/bin/env bash
# Run one coding task three ways and keep what each did: OpenCode on the local Qwen server, Claude Code on
# the local Qwen server, and Claude Code on a hosted model (docs/5-research/2026-10-19-local-qwen-notes.md,
# "Comparison"). The runs are headless, one after the other, each in a throwaway worktree of REPO at REV.
#   qwen-compare.sh --repo REPO --commit REV --prompt FILE --out DIR
#                   [--only opencode,qwen-claude,hosted] [--hosted-model MODEL] [--allow PATTERN]...
# Tools are approved without asking: OpenCode gets `run --auto`, and Claude Code gets acceptEdits with the
# --allow Bash patterns (by default Go's: "Bash(go *)", "Bash(GOWORK=off go *)", "Bash(gofmt *)", plus
# "Bash(git diff*)" and "Bash(git status*)"). The worktrees are throwaway, but the agents run on this host.
# Start the server first (qwen-local.sh start) for the local runs. The hosted run uses the personal config
# dir (QWEN_HOSTED_CONFIG_DIR, $HOME/.claude-personal) and MODEL (sonnet), so it uses that subscription.
# DIR, which must be new or empty, gets for each run <name>.out and <name>.err (the tool's output),
# <name>.patch (its diff, new files included) and <name>.server.log (the server log lines written during the
# run); summary.tsv (name, exit code, wall seconds); and rss.log (llama-server's memory every 30 seconds).
# The worktrees stay in DIR/wt-<name> for review; the cleanup commands are printed at the end.
# QWEN_COMPARE_TIMEOUT caps each run (1800 seconds). QWEN_COMPARE_OPENCODE, QWEN_COMPARE_QWEN_CLAUDE and
# QWEN_CLAUDE_BIN override the three commands.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=qwen-lib.sh
. "$HERE/qwen-lib.sh"
usage() { echo "usage: qwen-compare.sh --repo REPO --commit REV --prompt FILE --out DIR [--only LIST] [--hosted-model MODEL] [--allow PATTERN]..." >&2; exit 2; }

repo="" rev="" prompt="" out="" only="opencode,qwen-claude,hosted" model="sonnet" allow=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:?}"; shift 2 ;;
    --commit) rev="${2:?}"; shift 2 ;;
    --prompt) prompt="${2:?}"; shift 2 ;;
    --out) out="${2:?}"; shift 2 ;;
    --only) only="${2:?}"; shift 2 ;;
    --hosted-model) model="${2:?}"; shift 2 ;;
    --allow) allow+=("${2:?}"); shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$repo" ] && [ -n "$rev" ] && [ -n "$prompt" ] && [ -n "$out" ] || usage
[ ${#allow[@]} -gt 0 ] || allow=("Bash(go *)" "Bash(GOWORK=off go *)" "Bash(gofmt *)" "Bash(git diff*)" "Bash(git status*)")
IFS=, read -r -a runs <<< "$only"
for r in "${runs[@]}"; do
  case "$r" in opencode | qwen-claude | hosted) ;; *) echo "unknown run '$r'; use opencode, qwen-claude or hosted" >&2; usage ;; esac
done
[ -f "$prompt" ] || { echo "the prompt file $prompt does not exist" >&2; exit 2; }
if [ -d "$out" ] && [ -n "$(ls -A "$out")" ]; then echo "--out $out is not empty; give a new folder" >&2; exit 2; fi
mkdir -p "$out"
out="$(cd "$out" && pwd)"
text="$(cat "$prompt")"
log="$QWEN_HOME/logs/server.log"
stamp="$(date +%Y%m%d%H%M%S)-$$"
claude_flags=(--permission-mode acceptEdits --allowedTools "${allow[@]}" --output-format json)

# Sample llama-server's memory while the runs go, if it is running.
pidf="$QWEN_HOME/run/server.pid"
if [ -f "$pidf" ] && [ -r "/proc/$(cat "$pidf")/status" ]; then
  spid="$(cat "$pidf")"
  ( while [ -r "/proc/$spid/status" ]; do
      echo "$(date +%T) $(awk '/VmRSS/ {printf "%.2f GB", $2 / 1048576}' "/proc/$spid/status")" >> "$out/rss.log"
      sleep 30
    done ) &
  sampler=$!
  trap 'kill "$sampler" 2>/dev/null || true' EXIT
fi

for r in "${runs[@]}"; do
  wt="$out/wt-$r"
  git -C "$repo" worktree add -q -b "cmp-$r-$stamp" "$wt" "$rev"
  case "$r" in
    opencode) cmd=("${QWEN_COMPARE_OPENCODE:-$HERE/qwen-opencode.sh}" run --auto --format json "$text") ;;
    qwen-claude) cmd=("${QWEN_COMPARE_QWEN_CLAUDE:-$HERE/qwen-claude.sh}" -p "$text" "${claude_flags[@]}") ;;
    hosted) cmd=(env -u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_MODEL -u CLAUDE_CODE_MAX_CONTEXT_TOKENS
      CLAUDE_CONFIG_DIR="${QWEN_HOSTED_CONFIG_DIR:-$HOME/.claude-personal}"
      "${QWEN_CLAUDE_BIN:-$(command -v claude)}" --model "$model" -p "$text" "${claude_flags[@]}") ;;
  esac
  before=0
  [ ! -f "$log" ] || before="$(wc -l < "$log")"
  t0="$(date +%s)"
  rc=0
  (cd "$wt" && timeout "${QWEN_COMPARE_TIMEOUT:-1800}" "${cmd[@]}") > "$out/$r.out" 2> "$out/$r.err" < /dev/null || rc=$?
  printf '%s\t%s\t%s\n' "$r" "$rc" "$(($(date +%s) - t0))" | tee -a "$out/summary.tsv"
  [ ! -f "$log" ] || tail -n +"$((before + 1))" "$log" > "$out/$r.server.log"
  git -C "$wt" add -A
  git -C "$wt" diff --cached > "$out/$r.patch"
done

echo "Results in $out. Review the worktrees, then remove them:"
for r in "${runs[@]}"; do
  echo "  git -C $repo worktree remove --force $out/wt-$r && git -C $repo branch -D cmp-$r-$stamp"
done

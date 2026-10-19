#!/usr/bin/env bash
# Run Claude Code against the local Qwen 3.8 27B server, in a config dir of its own that has no
# account (docs/5-research/2026-10-19-local-qwen-design.md). Start the server first: qwen-local.sh start.
#   qwen-claude.sh init                set up the config dir: the personal setup's plugins, skills and
#                                      merge hook, without its account, memory or account guard
#   qwen-claude.sh [CLAUDE ARGS...]    run Claude Code on the local model
# Environment, besides qwen-lib.sh's:
#   QWEN_CLAUDE_DIR    the local config dir ($HOME/.claude-qwen); never the work or personal one
#   QWEN_PERSONAL_DIR  the personal config dir, only read ($HOME/.claude-personal)
#   QWEN_CLAUDE_BIN    the claude binary (the one on PATH; the zsh `claude` function is not used)
# Claude Code does not know this model, so CLAUDE_CODE_MAX_CONTEXT_TOKENS tells it the server's context.
# It never writes to ~/.claude, ~/.claude.json or the personal config dir, and removes the cloud
# credentials of the caller's shell, so a session cannot reach a hosted model by accident.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=qwen-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/qwen-lib.sh"

dir="${QWEN_CLAUDE_DIR:-$HOME/.claude-qwen}"
personal="${QWEN_PERSONAL_DIR:-$HOME/.claude-personal}"
bin="${QWEN_CLAUDE_BIN:-$(command -v claude || true)}"
[ -n "$bin" ] || { echo "claude is not on PATH; set QWEN_CLAUDE_BIN" >&2; exit 2; }
plugins=(superpowers gopls-lsp skill-creator)
market=claude-plugins-official

# inside DIR ROOT: DIR is ROOT or a path under it, after resolving links.
inside() {
  local d r
  d="$(realpath -m "$1")" r="$(realpath -m "$2")"
  [ "$d" = "$r" ] || [[ "$d" == "$r"/* ]]
}

# Both modes refuse a config dir that is, or is inside, a real account's config dir, and one that holds
# them (such as $HOME, where ~/.claude.json lives): Claude Code would write that account's files.
for r in "$HOME/.claude" "$HOME/.claude-personal" "$personal"; do
  if inside "$dir" "$r" || inside "$r" "$dir"; then
    echo "QWEN_CLAUDE_DIR $dir overlaps the account config dir $r; the local config dir must be separate" >&2
    exit 2
  fi
done

if [ "${1:-}" = init ]; then
  mkdir -p "$dir"
  enabled="" sep=""
  for p in "${plugins[@]}"; do enabled+="$sep\"$p@$market\":true"; sep=","; done
  printf '{"permissions":{"defaultMode":"default"},"model":"%s","enabledPlugins":{%s},"extraKnownMarketplaces":{"%s":{"source":{"source":"github","repo":"anthropics/%s"}}},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/hooks/merge-requires-green.sh"}]}]}}\n' \
    "$QWEN_ALIAS" "$enabled" "$market" "$market" "$personal" > "$dir/settings.json"
  [ -e "$dir/.claude.json" ] || echo '{"hasCompletedOnboarding":true}' > "$dir/.claude.json"
  [ -L "$dir/skills" ] || ln -s "$personal/skills" "$dir/skills"
  CLAUDE_CONFIG_DIR="$dir" "$bin" plugin marketplace add "anthropics/$market"
  for p in "${plugins[@]}"; do CLAUDE_CONFIG_DIR="$dir" "$bin" plugin install "$p@$market"; done
  echo "set up $dir; run scripts/qwen-claude.sh to start a session"
  exit 0
fi

[ -f "$dir/settings.json" ] || { echo "$dir is not set up; run scripts/qwen-claude.sh init first" >&2; exit 2; }
qwen_require_server
# The Bedrock, Vertex and Foundry switches would send the session to a hosted model, past the base URL.
exec env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN -u OPENROUTER_API_KEY \
  -u CLAUDE_CODE_USE_BEDROCK -u CLAUDE_CODE_USE_VERTEX -u CLAUDE_CODE_USE_FOUNDRY \
  -u ANTHROPIC_BEDROCK_BASE_URL -u ANTHROPIC_VERTEX_BASE_URL \
  CLAUDE_CONFIG_DIR="$dir" ANTHROPIC_BASE_URL="$(qwen_url)" ANTHROPIC_AUTH_TOKEN=local-qwen \
  ANTHROPIC_MODEL="$QWEN_ALIAS" ANTHROPIC_DEFAULT_OPUS_MODEL="$QWEN_ALIAS" ANTHROPIC_DEFAULT_SONNET_MODEL="$QWEN_ALIAS" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$QWEN_ALIAS" CLAUDE_CODE_SUBAGENT_MODEL="$QWEN_ALIAS" \
  CLAUDE_CODE_MAX_CONTEXT_TOKENS="$QWEN_CTX" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_AUTOUPDATER=1 \
  "$bin" "$@"

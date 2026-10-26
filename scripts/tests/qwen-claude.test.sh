#!/usr/bin/env bash
# Each check is a condition string run by eval: $rc and the helpers are read there, so
# the linter cannot see them used.
# shellcheck disable=SC2016,SC2034,SC2329
# Tests for qwen-claude.sh.   scripts/tests/qwen-claude.test.sh
# A fake `claude` and a fake ygg-models.sh stand in for the real tools: no server, no account, no network.
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
run() { rm -f "$T/calls" "$T/env"; "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }
called() { grep -qx -F -- "$1" "$T/calls"; }
envhas() { grep -qx -F -- "$1" "$T/env"; }
# js FILE EXPR: evaluate a python expression over the JSON file (as c).
js() { python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); sys.exit(0 if eval(sys.argv[2]) else 1)' "$1" "$2"; }
sums() { find "$HOME/.claude-personal" "$HOME/.claude" "$HOME/.claude.json" -type f -exec sha256sum {} + | sort; }
export HOME="$T/home"
P="$HOME/.claude-personal" Q="$HOME/.claude-qwen"
mkdir -p "$P/skills/a" "$P/hooks" "$HOME/.claude"
echo '{"model":"opus"}' > "$P/settings.json"
echo 'skill a' > "$P/skills/a/SKILL.md"
printf '#!/bin/sh\nexit 0\n' > "$P/hooks/merge-requires-green.sh"
echo '{"model":"work"}' > "$HOME/.claude/settings.json"
echo '{"work":true}' > "$HOME/.claude.json"
before="$(sums)"

# The fake claude records each call as one line, "<CLAUDE_CONFIG_DIR> <args...>", and its environment.
mkdir -p "$T/bin"
cat > "$T/bin/claude" <<EOF2
#!/usr/bin/env bash
echo "\${CLAUDE_CONFIG_DIR:-none} \$*" >> "$T/calls"
env > "$T/env"
EOF2
# A fake ygg-models.sh (QWEN_MODELS_SH) stands in for the real one: `status` answers while $T/healthy exists.
cat > "$T/ygg-models.sh" <<EOF2
#!/usr/bin/env bash
[ "\$1" = status ] || exit 64
[ -e "$T/healthy" ] || { echo "not running"; exit 3; }
echo "running on http://127.0.0.1:8088, loaded: none"
EOF2
chmod +x "$T/ygg-models.sh"
chmod +x "$T/bin/claude"
export PATH="$T/bin:$PATH" QWEN_HOME="$T/qh" QWEN_MODELS_SH="$T/ygg-models.sh" QWEN_CLAUDE_BIN="$T/bin/claude"
C="$S/qwen-claude.sh"

run bash "$C" -p hi
check "run before init: refuses and says to init first; claude does not run" \
  eval '[ $rc = 2 ] && has "qwen-claude.sh init" && [ ! -e "$T/calls" ]'

QWEN_CLAUDE_DIR="$P" run bash "$C" init
check "init refuses the personal config dir, and writes nothing" \
  eval '[ $rc = 2 ] && [ ! -e "$T/calls" ] && [ "$(sums)" = "$before" ]'
QWEN_CLAUDE_DIR="$HOME/.claude/sub" run bash "$C" init
check "init refuses a dir inside the work config dir" eval '[ $rc = 2 ] && [ ! -e "$HOME/.claude/sub" ]'
QWEN_CLAUDE_DIR="$HOME" run bash "$C" init
check "init refuses \$HOME, which holds both config dirs and ~/.claude.json" eval '[ $rc = 2 ] && [ ! -e "$T/calls" ] && [ ! -e "$HOME/settings.json" ]'
QWEN_PERSONAL_DIR="$T/elsewhere" QWEN_CLAUDE_DIR="$P" run bash "$C" init
check "init refuses ~/.claude-personal even when QWEN_PERSONAL_DIR points elsewhere" eval '[ $rc = 2 ] && [ ! -e "$T/calls" ]'

run bash "$C" init
check "init writes settings: the three plugins, ask-before-acting mode, the personal merge hook" \
  eval '[ $rc = 0 ] && js "$Q/settings.json" "c[\"permissions\"][\"defaultMode\"] == \"default\" and sorted(c[\"enabledPlugins\"]) == [\"gopls-lsp@claude-plugins-official\", \"skill-creator@claude-plugins-official\", \"superpowers@claude-plugins-official\"] and c[\"hooks\"][\"PreToolUse\"][0][\"hooks\"][0][\"command\"] == \"$P/hooks/merge-requires-green.sh\" and c[\"model\"] == \"qwen3.8-27b\""'
check "init marks onboarding done and links the personal skills" \
  eval 'js "$Q/.claude.json" "c[\"hasCompletedOnboarding\"] is True" && [ "$(readlink "$Q/skills")" = "$P/skills" ]'
check "init adds the marketplace and installs the three plugins, all into the local config dir" \
  eval 'called "$Q plugin marketplace add anthropics/claude-plugins-official" && called "$Q plugin install superpowers@claude-plugins-official" && called "$Q plugin install gopls-lsp@claude-plugins-official" && called "$Q plugin install skill-creator@claude-plugins-official"'

echo '{"hasCompletedOnboarding":true,"mine":1}' > "$Q/.claude.json"
run bash "$C" init
check "init again keeps an existing .claude.json and the skills link" \
  eval '[ $rc = 0 ] && js "$Q/.claude.json" "c.get(\"mine\") == 1" && [ "$(readlink "$Q/skills")" = "$P/skills" ]'

run bash "$C" -p hi
check "run with the server down: refuses with the start hint; claude does not run" \
  eval '[ $rc = 2 ] && has "ygg-models.sh start" && [ ! -e "$T/calls" ]'

touch "$T/healthy"
QWEN_CLAUDE_DIR="$HOME/.claude" run bash "$C" -p hi
check "run refuses the work config dir, though it has a settings.json" eval '[ $rc = 2 ] && [ ! -e "$T/calls" ]'
QWEN_CLAUDE_DIR="$P" run bash "$C" -p hi
check "run refuses the personal config dir" eval '[ $rc = 2 ] && [ ! -e "$T/calls" ]'

CLAUDE_CODE_USE_BEDROCK=1 CLAUDE_CODE_USE_VERTEX=1 CLAUDE_CODE_USE_FOUNDRY=1 ANTHROPIC_BEDROCK_BASE_URL=x ANTHROPIC_VERTEX_BASE_URL=y \
ANTHROPIC_API_KEY=a CLAUDE_CODE_OAUTH_TOKEN=b OPENROUTER_API_KEY=c run bash "$C" -p "hi there"
check "run passes the arguments and points Claude Code at the local server and config dir" \
  eval '[ $rc = 0 ] && called "$Q -p hi there" && envhas "ANTHROPIC_BASE_URL=http://127.0.0.1:8088" && envhas "CLAUDE_CONFIG_DIR=$Q" && envhas ANTHROPIC_MODEL=qwen3.8-27b && envhas ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3.8-27b && envhas CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 && envhas DISABLE_AUTOUPDATER=1 && envhas CLAUDE_CODE_MAX_CONTEXT_TOKENS=102400'
check "no cloud credential from the caller's shell reaches claude" \
  eval '[ -e "$T/env" ] && ! grep -Eq "^(ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN|OPENROUTER_API_KEY)=" "$T/env"'
check "no Bedrock, Vertex or Foundry switch reaches claude, so it cannot bypass the local base URL" \
  eval '[ -e "$T/env" ] && ! grep -Eq "^(CLAUDE_CODE_USE_BEDROCK|CLAUDE_CODE_USE_VERTEX|CLAUDE_CODE_USE_FOUNDRY|ANTHROPIC_BEDROCK_BASE_URL|ANTHROPIC_VERTEX_BASE_URL)=" "$T/env"'
check "nothing under ~/.claude-personal or ~/.claude changed" eval '[ "$(sums)" = "$before" ]'

exit $fail

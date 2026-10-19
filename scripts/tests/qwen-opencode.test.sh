#!/usr/bin/env bash
# Each check is a condition string run by eval: $rc and the helpers are read there, so
# the linter cannot see them used.
# shellcheck disable=SC2016,SC2034,SC2329
# Tests for qwen-opencode.sh.   scripts/tests/qwen-opencode.test.sh
# A fake `opencode` and a fake `curl` stand in for the real tools: no server, no network.
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
run() { rm -f "$T/args" "$T/env"; "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }
envhas() { grep -qx -F -- "$1" "$T/env"; }
# conf EXPR: evaluate a python expression over the config the fake opencode was given (as c).
conf() { python3 -I -c 'import json,sys; c=json.loads(sys.argv[1]); sys.exit(0 if eval(sys.argv[2]) else 1)' \
  "$(sed -n 's/^OPENCODE_CONFIG_CONTENT=//p' "$T/env")" "$1"; }
export HOME="$T/home"; mkdir -p "$HOME"

mkdir -p "$T/bin"
cat > "$T/bin/opencode" <<EOF2
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$T/args"
env > "$T/env"
EOF2
cat > "$T/bin/curl" <<EOF2
#!/usr/bin/env bash
[ -e "$T/healthy" ] || exit 7
echo '{"status":"ok"}'
EOF2
chmod +x "$T/bin/opencode" "$T/bin/curl"
export PATH="$T/bin:$PATH" QWEN_HOME="$T/qh"
O="$S/qwen-opencode.sh"

run bash "$O" run hi
check "server down: refuses with the start hint, and opencode does not run" \
  eval '[ $rc = 2 ] && has "qwen-local.sh start" && [ ! -e "$T/args" ]'

touch "$T/healthy"; mkdir -p "$T/qh/run"; printf 'QWEN_PORT=9000\nQWEN_CTX=65536\n' > "$T/qh/run/server.env"
ANTHROPIC_API_KEY=a CLAUDE_CODE_OAUTH_TOKEN=b OPENROUTER_API_KEY=c run bash "$O" run "hi there"
check "the config points at the running server's port and context, and only at the local provider" \
  eval '[ $rc = 0 ] && conf "c[\"provider\"][\"qwen-local\"][\"options\"][\"baseURL\"] == \"http://127.0.0.1:9000/v1\"" && conf "c[\"provider\"][\"qwen-local\"][\"models\"][\"qwen3.8-27b\"][\"limit\"][\"context\"] == 65536" && conf "c[\"enabled_providers\"] == [\"qwen-local\"]"'
check "the model and the small model are both the local one; sharing and updates are off" \
  eval 'conf "c[\"model\"] == c[\"small_model\"] == \"qwen-local/qwen3.8-27b\"" && conf "c[\"share\"] == \"disabled\" and c[\"autoupdate\"] is False"'
check "run gets --standalone, so a background service with an older config is never used" \
  eval '[ "$(cat "$T/args")" = "$(printf "run\n--standalone\nhi there")" ]'
check "OpenCode does not read ~/.claude (the work account) or outside skills, and does not update, share or fetch models" \
  eval 'envhas OPENCODE_DISABLE_CLAUDE_CODE=1 && envhas OPENCODE_DISABLE_EXTERNAL_SKILLS=1 && envhas OPENCODE_DISABLE_AUTOUPDATE=true && envhas OPENCODE_DISABLE_SHARE=true && envhas OPENCODE_DISABLE_MODELS_FETCH=true'
check "no cloud credential from the caller's shell reaches opencode" \
  eval '[ -e "$T/env" ] && ! grep -Eq "^(ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN|OPENROUTER_API_KEY)=" "$T/env"'

run bash "$O"
check "the interactive session gets --standalone too" eval '[ $rc = 0 ] && [ "$(cat "$T/args")" = "--standalone" ]'
run bash "$O" ./some/project
check "a project folder for the interactive session follows --standalone" \
  eval '[ "$(cat "$T/args")" = "$(printf -- "--standalone\n./some/project")" ]'
exit $fail

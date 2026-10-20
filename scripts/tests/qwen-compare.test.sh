#!/usr/bin/env bash
# Each check is a condition string run by eval: $rc and the helpers are read there, so
# the linter cannot see them used.
# shellcheck disable=SC2016,SC2034,SC2329
# Tests for qwen-compare.sh.   scripts/tests/qwen-compare.test.sh
# Fakes stand in for qwen-opencode.sh, qwen-claude.sh and claude: each records its arguments, folder and
# environment, appends a line to a fake server log, and changes a file. A temp git repo is the project.
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
run() { "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }
export HOME="$T/home"; mkdir -p "$HOME/.claude-personal"

R="$T/repo"
git init -q -b main "$R"
git -C "$R" config user.email t@example.com; git -C "$R" config user.name t
echo base > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q -m base
BASE="$(git -C "$R" rev-parse HEAD)"
echo later > "$R/a.txt"; git -C "$R" commit -q -am later

export QWEN_HOME="$T/qh"; mkdir -p "$QWEN_HOME/logs"; echo "old line" > "$QWEN_HOME/logs/server.log"
mkdir -p "$T/bin"
for f in opencode qwen-claude claude; do
  cat > "$T/bin/$f" <<EOF2
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$T/$f.args"
pwd > "$T/$f.pwd"
env > "$T/$f.env"
echo "request from $f" >> "$QWEN_HOME/logs/server.log"
echo "$f was here" > "$f.txt"
echo "$f output"
exit "\${FAKE_RC_$(echo "$f" | tr -- '-' '_'):-0}"
EOF2
  chmod +x "$T/bin/$f"
done
export QWEN_COMPARE_OPENCODE="$T/bin/opencode" QWEN_COMPARE_QWEN_CLAUDE="$T/bin/qwen-claude" QWEN_CLAUDE_BIN="$T/bin/claude"
echo "Fix the bug. Do not ask questions." > "$T/prompt.txt"
X="$S/qwen-compare.sh"

run bash "$X" --repo "$R" --commit "$BASE"
check "missing --prompt or --out is a usage error" eval '[ $rc = 2 ] && has usage'

mkdir -p "$T/full"; touch "$T/full/x"
run bash "$X" --repo "$R" --commit "$BASE" --prompt "$T/prompt.txt" --out "$T/full"
check "an --out folder that is not empty is refused" eval '[ $rc = 2 ] && has "not empty"'

O="$T/cmp"
ANTHROPIC_BASE_URL=http://127.0.0.1:8088 FAKE_RC_qwen_claude=3 run bash "$X" --repo "$R" --commit "$BASE" --prompt "$T/prompt.txt" --out "$O"
check "all three runs happen, in their own worktrees at the asked commit" \
  eval '[ $rc = 0 ] && for t in opencode qwen-claude hosted; do [ "$(git -C "$O/wt-$t" rev-parse HEAD)" = "$BASE" ] || exit 1; done'
check "each tool runs in its own worktree" \
  eval '[ "$(cat "$T/opencode.pwd")" = "$O/wt-opencode" ] && [ "$(cat "$T/qwen-claude.pwd")" = "$O/wt-qwen-claude" ] && [ "$(cat "$T/claude.pwd")" = "$O/wt-hosted" ]'
check "OpenCode gets run --auto --format json and the prompt" \
  eval '[ "$(head -n 4 "$T/opencode.args")" = "$(printf "run\n--auto\n--format\njson")" ] && grep -qxF "Fix the bug. Do not ask questions." "$T/opencode.args"'
check "local Claude Code gets the prompt, acceptEdits and the default Go allowlist, with JSON output" \
  eval 'grep -qx -- -p "$T/qwen-claude.args" && grep -qx acceptEdits "$T/qwen-claude.args" && grep -qxF "Bash(go *)" "$T/qwen-claude.args" && grep -qx json "$T/qwen-claude.args"'
check "hosted Claude Code uses the personal config dir, Sonnet by default, and never the local base URL" \
  eval 'grep -qx "CLAUDE_CONFIG_DIR=$HOME/.claude-personal" "$T/claude.env" && grep -qx sonnet "$T/claude.args" && ! grep -q "^ANTHROPIC_BASE_URL=" "$T/claude.env"'
check "the summary has each run's exit code and wall time; a failed run does not stop the others" \
  eval 'grep -qP "^opencode\t0\t[0-9]+$" "$O/summary.tsv" && grep -qP "^qwen-claude\t3\t[0-9]+$" "$O/summary.tsv" && grep -qP "^hosted\t0\t[0-9]+$" "$O/summary.tsv"'
check "each run's output and diff (new files included) are saved" \
  eval 'grep -q "opencode output" "$O/opencode.out" && grep -q "+opencode was here" "$O/opencode.patch" && grep -q "+claude was here" "$O/hosted.patch"'
check "each run gets only its own slice of the server log" \
  eval '[ "$(cat "$O/opencode.server.log")" = "request from opencode" ] && [ "$(cat "$O/qwen-claude.server.log")" = "request from qwen-claude" ]'
check "the cleanup commands are printed, and the worktrees are left for review" \
  eval 'has "worktree remove --force $O/wt-opencode" && has "branch -D" && [ -d "$O/wt-hosted" ]'

run bash "$X" --repo "$R" --commit "$BASE" --prompt "$T/prompt.txt" --out "$T/only" --only hosted --hosted-model opus \
  --allow "Bash(npm test*)"
check "--only, --hosted-model and --allow choose the runs, the model and the allowlist" \
  eval '[ $rc = 0 ] && [ -d "$T/only/wt-hosted" ] && [ ! -e "$T/only/wt-opencode" ] && grep -qx opus "$T/claude.args" && grep -qxF "Bash(npm test*)" "$T/claude.args" && ! grep -qxF "Bash(go *)" "$T/claude.args"'

run bash "$X" --repo "$R" --commit "$BASE" --prompt "$T/prompt.txt" --out "$T/bad" --only gemini
check "an unknown run name is a usage error" eval '[ $rc = 2 ] && has gemini && [ ! -e "$T/bad/wt-gemini" ]'

exit $fail

#!/usr/bin/env bash
# Tests for ygg-reviewer-bench.sh (B-108).   scripts/tests/ygg-reviewer-bench.test.sh
# A fake opencode (YGG_REVIEWER_BENCH_OPENCODE) prints canned sessions: no model, no network, no money.
# Each check is a condition string run by eval: $rc and the helpers are read there, so the linter cannot
# see them used.
# shellcheck disable=SC2016,SC2034,SC2329
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/.."
B="$S/ygg-reviewer-bench.sh"
F="$S/testdata/reviewer-bench"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
run() { "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
calls() { cat "$T/calls/count" 2>/dev/null || echo 0; }
envhas() { grep -qx -F -- "$1" "$T/calls/1.env"; }
export HOME="$T/home" TMPDIR="$T/tmp"
mkdir -p "$HOME" "$TMPDIR"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset OPENROUTER_API_KEY ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN

# A made-up odin with the reviewer prompt, and a made-up mimir with the brief.
O="$T/odin"; mkdir -p "$O/testdata/smoke-grade/prompts"
printf 'Review the work in this repository. REVIEW-PROMPT-MARK\n' >"$O/testdata/smoke-grade/prompts/review.md"
M="$T/mimir"; mkdir -p "$M/smoke-notes"
printf '# Notes: product brief\n\nBRIEF-MARK\n' >"$M/smoke-notes/instruction.md"
common=(--odin "$O" --tasks "$M")

# The fake opencode: it keeps what it was given, writes a file into its folder, prints the canned session
# of its number and exits with the canned code (0 by default).
mkdir -p "$T/bin"
cat >"$T/bin/opencode" <<EOF
#!/usr/bin/env bash
n=\$((\$(cat "$T/calls/count" 2>/dev/null || echo 0) + 1))
echo "\$n" >"$T/calls/count"
printf '%s\n' "\$@" >"$T/calls/\$n.args"
env >"$T/calls/\$n.env"
pwd >"$T/calls/\$n.pwd"
ls -A >"$T/calls/\$n.ls"
cat >"$T/calls/\$n.stdin"
echo planted >"written-by-session-\$n"
cat "$T/answers/\$n.jsonl" 2>/dev/null
exit "\$(cat "$T/answers/\$n.exit" 2>/dev/null || echo 0)"
EOF
chmod +x "$T/bin/opencode"
export YGG_REVIEWER_BENCH_OPENCODE="$T/bin/opencode"
fresh() { rm -rf -- "$T/calls" "$T/answers"; mkdir -p "$T/calls" "$T/answers"; }

# canned N TEXT [COST]: session N reads in a first step (with a sentence that is not the answer) and answers
# TEXT in a second. In all: 3000 new tokens in, 7000 from the cache, 100 out and 400 of reasoning, COST dollars.
canned() {
  python3 -I - "$T/answers/$1.jsonl" "$2" "${3:-0.004}" <<'PY'
import json, sys
path, text, cost = sys.argv[1], sys.argv[2], float(sys.argv[3])
def fin(reason, i, o, r, cr, c):
    return {"type": "step_finish", "part": {"type": "step-finish", "reason": reason, "cost": c,
            "tokens": {"total": i + o + r + cr, "input": i, "output": o, "reasoning": r, "cache": {"write": 0, "read": cr}}}}
ev = [{"type": "step_start", "part": {"type": "step-start"}},
      {"type": "text", "part": {"type": "text", "text": "I will read start.sh first."}},
      {"type": "tool_use", "part": {"type": "tool", "tool": "read", "state": {"status": "completed", "input": {"filePath": "start.sh"}}}},
      fin("tool-calls", 1000, 50, 0, 0, cost / 2),
      {"type": "step_start", "part": {"type": "step-start"}},
      {"type": "text", "part": {"type": "text", "text": text}},
      fin("stop", 2000, 50, 400, 7000, cost / 2)]
with open(path, "w") as f:
    for e in ev:
        f.write(json.dumps(e) + "\n")
PY
}
finding() { # finding ID LOCATION CLAIM [SOURCE] [STATUS]: one finding as JSON
  printf '{"id": "%s", "source": "%s", "severity": "major", "location": "%s", "claim": "%s", "status": "%s"}' \
    "$1" "${4:-review}" "$2" "$3" "${5:-open}"
}
fence() { printf '```json\n%s\n```' "$1"; }
P4RE='owner|another (user|person|account)|other (users?|person|people|accounts?)|any (user|person)|not theirs|not the caller|idor'

# --- the arguments ---
run bash "$B"
check "no arguments: usage, exit 2" eval '[ $rc = 2 ] && has "usage:"'
run bash "$B" --model qwen/qwen3.8-27b --leaf "$F/P4" --sessions 0 "${common[@]}"
check "zero sessions is refused" eval '[ $rc = 2 ] && has "--sessions"'
run bash "$B" --model qwen/qwen3.8-27b --leaf "$T/no-such-leaf" --sessions 1 "${common[@]}"
check "a missing leaf is refused" eval '[ $rc = 2 ] && has "no-such-leaf"'
run bash "$B" --model qwen/qwen3.8-27b --leaf "$F/P4" --sessions 1 --fault '(' "${common[@]}"
check "a fault pattern that is not a regular expression is refused" eval '[ $rc = 2 ] && has "--fault"'
run bash "$B" --model qwen/qwen3.8-27b --leaf "$F/P4" --sessions 1 --effort max "${common[@]}"
check "an unknown effort is refused" eval '[ $rc = 2 ] && has "--effort"'
run bash "$B" --model 'qwen/x"y' --leaf "$F/P4" --sessions 1 "${common[@]}"
check "a model name with a quote is refused" eval '[ $rc = 2 ] && has "--model"'
run bash "$B" --model qwen/qwen3.8-27b --leaf "$F/P4" --sessions 1 --odin "$T/nowhere" --tasks "$M"
check "an odin without the smoke reviewer prompt is refused" eval '[ $rc = 2 ] && has "review.md"'

# --- the dry run: prints the commands, runs nothing, needs no key ---
fresh
run bash "$B" --dry-run --model qwen/qwen3.8-27b --leaf "$F/P4" --sessions 8 --fault "$P4RE" --out "$T/dry" "${common[@]}"
check "dry run: exit 0, and opencode never runs" eval '[ $rc = 0 ] && [ "$(calls)" = 0 ] && has "spends nothing"'
check "dry run: the command is opencode run, standalone, JSON events, the OpenRouter model" \
  eval 'has "run --standalone --format json -m openrouter/qwen/qwen3.8-27b"'
check "dry run: strict provider settings (no data kept, zero retention, no fallback), effort high" \
  eval 'has "\"data_collection\":\"deny\"" && has "\"zdr\":true" && has "\"allow_fallbacks\":false" && has "\"effort\":\"high\""'
check "dry run: read-only permissions, and the graph's 10 turns" \
  eval 'has "\"edit\":\"deny\"" && has "\"bash\":\"deny\"" && has "\"external_directory\":\"deny\"" && has "\"steps\":10"'
check "dry run: the key is a reference to the environment, never a value" eval 'has "{env:OPENROUTER_API_KEY}"'
check "dry run: XDG_DATA_HOME is set, outside HOME" \
  eval 'has "XDG_DATA_HOME=" && ! grep -q "XDG_DATA_HOME=[^ ]*$HOME" "$T/out"'
check "dry run: the prompt is written, from odin's review.md, the brief and the report format" \
  eval 'grep -q REVIEW-PROMPT-MARK "$T/dry/prompt.md" && grep -q "^## Brief$" "$T/dry/prompt.md" && grep -q BRIEF-MARK "$T/dry/prompt.md" && grep -q "Your id is review" "$T/dry/prompt.md"'
run bash "$B" --dry-run --model openrouter/qwen/qwen3.8-27b --leaf "$F/P4" --sessions 1 --effort off --out "$T/dry2" "${common[@]}"
check "dry run: an openrouter/ prefix is accepted, and effort off names no effort" \
  eval '[ $rc = 0 ] && has "-m openrouter/qwen/qwen3.8-27b" && hasnt "openrouter/openrouter" && hasnt "\"effort\""'

# --- a real run needs the key ---
fresh
run bash "$B" --model qwen/qwen3.8-27b --leaf "$F/P4" --sessions 1 --out "$T/nokey" "${common[@]}"
check "no OPENROUTER_API_KEY: refused before any session" eval '[ $rc = 2 ] && has "OPENROUTER_API_KEY" && [ "$(calls)" = 0 ]'

# --- five sessions with the fake: the table ---
fresh
canned 1 "The work breaks the brief.

$(fence "{\"findings\": [$(finding cross-user-delete notes.js:18 "remove deletes any note by id: one person's DELETE reaches another user's note")]}")"
canned 2 $'\n\n{"findings": []}'
canned 3 "What would you like help with?"
canned 4 "$(fence "{\"findings\": [$(finding find-index server.js:174 "findIndex is not a JavaScript method")]}")"
canned 5 "$(fence '{"findings": []}')
That is all."
export OPENROUTER_API_KEY=made-up-key ANTHROPIC_API_KEY=made-up-a CLAUDE_CODE_OAUTH_TOKEN=made-up-b
# Host settings that must not reach a session: OpenCode variables and anything else of the caller's shell.
export OPENCODE_PERMISSION=x OPENCODE_CONFIG=/x HOST_ONLY_VAR=y
run bash "$B" --model qwen/qwen3.8-27b --leaf "$F/P4" --sessions 5 --fault "$P4RE" --out "$T/five" "${common[@]}"
check "five sessions: exit 0 and five calls" eval '[ $rc = 0 ] && [ "$(calls)" = 5 ]'
check "the table: 3 valid reports, findings per session, 1 fault found, average tokens and cost" \
  eval 'has "| P4 | qwen/qwen3.8-27b | 5 | 3 | 1, 0, -, 1, - | 1 | 10.0k (3.0k) | 0.5k | \$0.004 |"'
check "the table has the journal's columns" \
  eval 'has "| Leaf | Model | Sessions | Valid reports | Findings per session | Fault found | Tokens in (new) | Tokens out | Cost per session |"'
check "each session says why its report is not valid" \
  eval 'has "session 3: not a valid report: the answer does not end with a JSON document" && has "session 5: not a valid report: text after the report"'
check "the claims are printed, and the one that matches the fault is marked" \
  eval 'has "fault found" && has "reaches another user" && has "findIndex is not a JavaScript method"'
check "the summary and each session's events are kept in the out folder" \
  eval 'grep -q "| P4 |" "$T/five/summary.md" && [ -s "$T/five/session-1.jsonl" ] && [ -s "$T/five/session-5.jsonl" ]'
check "the runner gets the command line: run, standalone, JSON events, the model" \
  eval '[ "$(cat "$T/calls/1.args")" = "$(printf "run\n--standalone\n--format\njson\n-m\nopenrouter/qwen/qwen3.8-27b")" ]'
check "the prompt goes on stdin: odin's review.md, the brief, the report format, the reviewer id and the passed check" \
  eval 'grep -q REVIEW-PROMPT-MARK "$T/calls/1.stdin" && grep -q BRIEF-MARK "$T/calls/1.stdin" && grep -q "end your answer with the document" "$T/calls/1.stdin" && grep -q "Your id is review" "$T/calls/1.stdin" && grep -q "The checks that passed on this work: unit." "$T/calls/1.stdin"'
check "the session runs in a copy of the leaf, never in the leaf itself" \
  eval '[ "$(cat "$T/calls/1.pwd")" != "$(cd "$F/P4" && pwd)" ] && grep -qx notes.js "$T/calls/1.ls" && grep -qx server.js "$T/calls/1.ls" && ! ls "$F/P4" | grep -q written-by'
check "each session gets a fresh copy" eval '[ -s "$T/calls/2.ls" ] && ! grep -q written-by "$T/calls/2.ls"'
check "the copy is a git repository with one commit, so OpenCode's project is the copy" \
  eval 'grep -qx .git "$T/calls/1.ls"'
check "the OpenRouter key reaches the runner; the Anthropic credentials do not" \
  eval 'grep -qx OPENROUTER_API_KEY=made-up-key "$T/calls/1.env" && ! grep -Eq "^(ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN)=" "$T/calls/1.env"'
check "OpenCode reads no project or Claude Code config and does not update, share or fetch models" \
  eval 'envhas OPENCODE_DISABLE_PROJECT_CONFIG=1 && envhas OPENCODE_DISABLE_CLAUDE_CODE=1 && envhas OPENCODE_DISABLE_EXTERNAL_SKILLS=1 && envhas OPENCODE_DISABLE_AUTOUPDATE=true && envhas OPENCODE_DISABLE_SHARE=true && envhas OPENCODE_DISABLE_MODELS_FETCH=true'
d1="$(sed -n 's/^XDG_DATA_HOME=//p' "$T/calls/1.env")"
d2="$(sed -n 's/^XDG_DATA_HOME=//p' "$T/calls/2.env")"
c1="$(sed -n 's/^XDG_CONFIG_HOME=//p' "$T/calls/1.env")"
c2="$(sed -n 's/^XDG_CONFIG_HOME=//p' "$T/calls/2.env")"
check "no OpenCode variable and no other variable of the caller's shell reaches the session" \
  eval '[ -s "$T/calls/1.env" ] && ! grep -Eq "^(OPENCODE_PERMISSION|OPENCODE_CONFIG|HOST_ONLY_VAR)=" "$T/calls/1.env"'
check "each session has its own XDG_CONFIG_HOME, in the work folder, so no global OpenCode config applies" \
  eval '[ -n "$c1" ] && [ "$c1" != "$c2" ] && case "$c1" in "$TMPDIR"/ygg-reviewer-bench-work.*/config-1) true ;; *) false ;; esac'
check "each session has its own XDG_DATA_HOME, outside HOME" \
  eval '[ -n "$d1" ] && [ "$d1" != "$d2" ] && case "$d1" in "$HOME"/*) false ;; *) true ;; esac'
check "the config reaches the runner with the strict provider settings and the read-only permissions" \
  eval 'grep -q "^OPENCODE_CONFIG_CONTENT=.*\"zdr\":true" "$T/calls/1.env" && grep -q "^OPENCODE_CONFIG_CONTENT=.*\"question\":\"deny\"" "$T/calls/1.env"'

# --- a model that OpenRouter reports no cost for ---
fresh
canned 1 '{"findings": []}' 0
canned 2 '{"findings": []}' 0
run bash "$B" --model anthropic/claude-haiku-5.5 --leaf "$F/P0" --sessions 2 --out "$T/zero" "${common[@]}"
check "cost 0 with tokens prints as unknown, never \$0.00" \
  eval '[ $rc = 0 ] && has "| P0 | anthropic/claude-haiku-5.5 | 2 | 2 | 0, 0 | - | 10.0k (3.0k) | 0.5k | unknown |" && hasnt "\$0.00"'

# --- what counts as a valid report: the engine's rules ---
fresh
canned 1 "$(fence '{"findings": []}') and $(fence '{"findings": []}')"
canned 2 "{\"findings\": [$(finding a server.js:1 "x" reviewer)]}"
canned 3 "{\"findings\": [$(finding a server.js "x")]}"
canned 4 "{\"findings\": [$(finding a server.js:1 "x" review fixed)]}"
canned 5 "{\"findings\": [$(finding a server.js:1 "x"), $(finding a server.js:2 "y")]}"
canned 6 'An example: {"findings": []} and my answer: {"findings": []}'
canned 7 "Here is my report: {\"findings\": [$(finding port start.sh:2 "the server listens on 8080")]}"
canned 8 '{"findings": []}'
echo 1 >"$T/answers/8.exit"
canned 9 "{\"findings\": [$(finding check-unit server.js:1 "x")]}"
canned 10 '{"findings": [], "summary": "fine"}'
run bash "$B" --model qwen/qwen3.8-27b --leaf "$F/P2" --sessions 10 --out "$T/rules" "${common[@]}"
check "only the bare report after prose is valid; with no --fault the fault column is -" \
  eval '[ $rc = 0 ] && has "| P2 | qwen/qwen3.8-27b | 10 | 1 | -, -, -, -, -, -, 1, -, -, - | - |"'
check "the reasons: two fences, a source, a location, a closed finding, an id twice, two documents, the exit code, a check id, an unknown field" \
  eval 'has "session 1: not a valid report: more than one code fence" && has "session 2: not a valid report" && has "session 3: not a valid report" && has "session 4: not a valid report" && has "session 5: not a valid report" && has "session 6: not a valid report: more than one document" && has "session 8: not a valid report: opencode exited 1" && has "session 9: not a valid report" && has "session 10: not a valid report"'

# --- the fixtures ---
lines() { diff "$1" "$2" | grep -c '^[<>]'; }
check "P1 to P3 are P0 with one line changed: the start.sh typo, the port, the order" \
  eval '[ "$(lines "$F/P0/start.sh" "$F/P1/start.sh")" = 2 ] && grep -q "node servr.js" "$F/P1/start.sh" && [ "$(lines "$F/P0/server.js" "$F/P2/server.js")" = 2 ] && grep -q "listen(8080" "$F/P2/server.js" && [ "$(lines "$F/P0/server.js" "$F/P3/server.js")" = 2 ]'
check "P4 reaches notes only through notes.of(email), and its remove ignores the owner" \
  eval 'grep -q "notes.of(email)" "$F/P4/server.js" && grep -q "return all.delete(id);" "$F/P4/notes.js" && ! grep -q "^const notes = new Map" "$F/P4/server.js"'
check "no fixture holds a .git" eval '[ -z "$(find "$F" -name .git)" ]'
check "the P4 fault pattern of the script's header is the one tested here" eval 'grep -qF -- "$P4RE" "$B"'
exit $fail

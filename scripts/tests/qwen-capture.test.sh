#!/usr/bin/env bash
# Each check is a condition string run by eval: the helpers are read there, so
# the linter cannot see them used.
# shellcheck disable=SC2016,SC2034,SC2329
# Tests for qwen-capture.py.   scripts/tests/qwen-capture.test.sh
# Starts the capture server on a free port, sends it requests with curl, and reads what it saved.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/.."
T="$(mktemp -d)"
cleanup() { [ -z "${CAP:-}" ] || kill "$CAP" 2>/dev/null; rm -rf -- "$T"; }
trap cleanup EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi
}

port="$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
python3 -I "$S/qwen-capture.py" "$port" "$T/cap" > "$T/log" 2>&1 & CAP=$!
for _ in $(seq 50); do curl -fsS -m 1 "http://127.0.0.1:$port/health" >/dev/null 2>&1 && break; sleep 0.1; done

curl -sS -m 5 -o "$T/r1" -w '%{http_code}' -H 'content-type: application/json' -d '{"model":"m","messages":[{"role":"system","content":"s"}]}' \
  "http://127.0.0.1:$port/v1/messages?beta=true" > "$T/code1"
curl -sS -m 5 -o /dev/null -H 'content-type: application/json' -d '{"model":"m","n":2}' "http://127.0.0.1:$port/v1/chat/completions"

check "the first request is saved by number and path, as sent" \
  eval '[ -f "$T/cap/00-v1_messages.json" ] && python3 -I -c "import json,sys; assert json.load(open(sys.argv[1]))[\"messages\"][0][\"role\"] == \"system\"" "$T/cap/00-v1_messages.json"'
check "the second request gets the next number" eval '[ -f "$T/cap/01-v1_chat_completions.json" ]'
check "each request is answered with an API error, so the tool stops instead of waiting" \
  eval '[ "$(cat "$T/code1")" = 500 ] && grep -q "\"type\": *\"error\"" "$T/r1"'
check "each saved request is announced on stdout" eval 'grep -q "00-v1_messages.json" "$T/log" && grep -q "01-v1_chat_completions.json" "$T/log"'
check "it listens on 127.0.0.1 only" eval '! curl -fsS -m 1 "http://$(hostname -I | cut -d" " -f1):$port/health" >/dev/null 2>&1'

exit $fail

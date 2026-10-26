#!/usr/bin/env bash
# Each check is a condition string run by eval: $rc and the helpers are read there, so
# the linter cannot see them used.
# shellcheck disable=SC2016,SC2034,SC2329
# Tests for qwen-measure.py.   scripts/tests/qwen-measure.test.sh
# A fake llama-server (a small Python HTTP server) answers /tokenize (one token per word) and
# /v1/chat/completions (fixed timings, and the prompt's word count as prompt_tokens). No GPU, no model.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/.."
T="$(mktemp -d)"
cleanup() { [ -z "${FAKE:-}" ] || kill "$FAKE" 2>/dev/null; rm -rf -- "$T"; }
trap cleanup EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
run() { "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }

cat > "$T/fake.py" <<'EOF2'
import http.server, json, sys
port_file, log = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["content-length"])))
        with open(log, "a") as f: f.write(json.dumps({"path": self.path, "body": body}) + "\n")
        if self.path == "/tokenize":
            out = {"tokens": list(range(len(body["content"].split())))}
        else:
            words = sum(len(m["content"].split()) for m in body["messages"])
            out = {"choices": [{"message": {"content": "ok", "reasoning_content": "think"}}],
                   "usage": {"prompt_tokens": words, "completion_tokens": 10},
                   "timings": {"prompt_n": words, "prompt_per_second": 1000.0, "predicted_n": 10,
                               "predicted_per_second": 50.0 + len(body["messages"]), "draft_n": 8, "draft_n_accepted": 6}}
        data = json.dumps(out).encode()
        self.send_response(200); self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(port_file, "w").write(str(s.server_port))
s.serve_forever()
EOF2
python3 -I "$T/fake.py" "$T/port" "$T/requests.log" & FAKE=$!
for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
QWEN_URL="http://127.0.0.1:$(cat "$T/port")"; export QWEN_URL
M="$S/qwen-measure.py"
echo "one two three four" > "$T/prompt.txt"

run python3 -I "$M" speed --runs 3 --max-tokens 64 "$T/prompt.txt"
check "speed: one line per run with the server's timings, then the medians" \
  eval '[ $rc = 0 ] && [ "$(grep -c "^run " "$T/out")" = 3 ] && has "decode 51.0 tokens/s" && has "draft 6/8" && has "median decode 51.0 tokens/s, median prompt 1000 tokens/s"'
check "speed: sends the prompt file and the token cap" \
  eval 'grep -q "\"max_tokens\": 64" "$T/requests.log" && grep -q "one two three four" "$T/requests.log"'

mkdir -p "$T/src"; for i in 1 2 3; do printf 'word%.0s ' $(seq 40) > "$T/src/f$i.go"; done
run python3 -I "$M" prompt --tokens 300 --question "What is it?" --out "$T/long.txt" "$T/src/*.go"
check "prompt: builds a prompt of about the asked size from the files, repeated, and ends with the question" \
  eval '[ $rc = 0 ] && has "tokens" && n=$(wc -w < "$T/long.txt") && [ "$n" -ge 280 ] && [ "$n" -le 330 ] && tail -c 20 "$T/long.txt" | grep -q "What is it?"'
run python3 -I "$M" prompt --tokens 300 --out "$T/none.txt" "$T/src/*.nothing"
check "prompt: no matching files is an error" eval '[ $rc = 2 ] && has "no files" && [ ! -e "$T/none.txt" ]'

run python3 -I "$M" growth --turns 3 --pid "$FAKE" --chunk 20 "$T/long.txt"
check "growth: one line per turn with the context, which grows, and the server's resident memory" \
  eval '[ $rc = 0 ] && [ "$(grep -c "^turn " "$T/out")" = 3 ] && has "rss" && a=$(sed -n "1s/.*ctx *\([0-9]*\).*/\1/p" "$T/out") && b=$(sed -n "3s/.*ctx *\([0-9]*\).*/\1/p" "$T/out") && [ "$b" -gt "$a" ]'
check "growth: each turn sends the whole conversation so far" \
  eval '[ "$(grep -c "/v1/chat/completions" "$T/requests.log")" -ge 3 ] && tail -n 1 "$T/requests.log" | grep -q "Turn 2" && tail -n 1 "$T/requests.log" | grep -q "Turn 0"'

run python3 -I "$M" growth --turns 1 --pid 999999999 "$T/long.txt"
check "growth: a pid that does not exist is an error" eval '[ $rc = 2 ] && has "999999999"'

QWEN_URL="http://127.0.0.1:1" run python3 -I "$M" speed --runs 1 "$T/prompt.txt"
check "speed: a server that does not answer is a clear error, not a traceback" \
  eval '[ $rc = 2 ] && has "ygg-models.sh start" && ! has Traceback'

exit $fail

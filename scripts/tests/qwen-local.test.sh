#!/usr/bin/env bash
# Each check is a condition string run by eval: $rc, $took and the helpers are read there, so
# the linter cannot see them used.
# shellcheck disable=SC2016,SC2034,SC2329
# Tests for qwen-local.sh and qwen-lib.sh.   scripts/tests/qwen-local.test.sh
# A fake `llama-server` and a fake `curl` stand in for the real tools: no GPU, no model, no network.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/.."
T="$(mktemp -d)"
cleanup() { pkill -f "$T/bin/llama-server" 2>/dev/null; [ -z "${SLEEPER:-}" ] || kill "$SLEEPER" 2>/dev/null; rm -rf -- "$T"; }
trap cleanup EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
run() { "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }
export HOME="$T/home"; mkdir -p "$HOME"

# The fake server writes its arguments, one per line, to $T/args, and marks itself healthy (for the fake
# curl) unless FAKE_NEVER_READY is set. FAKE_DIE makes it fail at once, as a model too big for VRAM does.
mkdir -p "$T/bin"
cat > "$T/bin/llama-server" <<EOF2
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$T/args"
echo "fake llama-server loading"
if [ -n "\${FAKE_DIE:-}" ]; then echo "fake: out of memory"; exit 1; fi
trap 'rm -f "$T/healthy"; kill \$! 2>/dev/null; exit 0' TERM
[ -n "\${FAKE_NEVER_READY:-}" ] || touch "$T/healthy"
sleep 300 & wait
EOF2
cat > "$T/bin/curl" <<EOF2
#!/usr/bin/env bash
[ -e "$T/healthy" ] || exit 7
echo '{"status":"ok"}'
EOF2
chmod +x "$T/bin/llama-server" "$T/bin/curl"
touch "$T/model.gguf"
export PATH="$T/bin:$PATH" QWEN_HOME="$T/qh" QWEN_LLAMA_SERVER="$T/bin/llama-server" QWEN_MODEL="$T/model.gguf" \
  QWEN_START_TIMEOUT=3
L="$S/qwen-local.sh"
pidf="$T/qh/run/server.pid" envf="$T/qh/run/server.env"
nservers() { pgrep -fc "$T/bin/llama-server"; }

# cmd
run bash "$L" cmd
check "cmd: binds 127.0.0.1:8088 with a 102400 context, a q8_0 KV cache, one slot and low effort" \
  eval '[ $rc = 0 ] && has "--host 127.0.0.1" && has "--port 8088" && has "-c 102400" && has "--cache-type-k q8_0" && has "--cache-type-v q8_0" && has "--parallel 1" && has "--reasoning-effort low"'
check "cmd: MTP is on by default, with the draft file from QWEN_HOME on the GPU" \
  eval 'has "--spec-type draft-mtp -md $T/qh/models/mtp.gguf -ngld all -ctkd q8_0 -ctvd q8_0"'
QWEN_EFFORT=off run bash "$L" cmd
check "cmd: effort off turns thinking off" eval 'has "--reasoning off" && ! has "--reasoning-effort"'
QWEN_EFFORT=high run bash "$L" cmd
check "cmd: an unknown effort is a usage error that names the allowed values" \
  eval '[ $rc = 2 ] && has QWEN_EFFORT && has "low, medium, xhigh, off"'
QWEN_MTP_ARGS="--spec-a x" run bash "$L" cmd
check "cmd: QWEN_MTP_ARGS ends the argument list" eval 'grep -Eq -- "--spec-a x ?\$" "$T/out"'
QWEN_MTP_ARGS="" run bash "$L" cmd
check "cmd: an empty QWEN_MTP_ARGS turns MTP off" eval '! has "--spec-a" && ! has "--spec-type"'

# start
QWEN_MODEL="$T/missing.gguf" run bash "$L" start
check "start: a missing model fails with its path, and starts nothing" \
  eval '[ $rc = 2 ] && has "$T/missing.gguf" && [ ! -e "$T/args" ]'

run bash "$L" start
check "start: waits for health, says where it is ready, and records the pid and the state" \
  eval '[ $rc = 0 ] && has "ready on http://127.0.0.1:8088" && kill -0 "$(cat "$pidf")" && grep -qx -- "-m" "$T/args" && grep -qx -- "$T/model.gguf" "$T/args" && grep -qx QWEN_PORT=8088 "$envf" && grep -qx QWEN_CTX=102400 "$envf"'

run bash "$L" start
check "start: a second start while running says so and starts no second server" \
  eval '[ $rc = 0 ] && has "already running" && [ "$(nservers)" = 1 ]'

run bash "$L" status
check "status: running exits 0 with the URL" eval '[ $rc = 0 ] && has running && has "http://127.0.0.1:8088"'

run bash "$L" stop
check "stop: the server is gone and the pid and state files are removed" \
  eval '[ $rc = 0 ] && [ "$(nservers)" = 0 ] && [ ! -e "$pidf" ] && [ ! -e "$envf" ]'

run bash "$L" stop
check "stop: not running is not an error" eval '[ $rc = 0 ] && has "not running"'

run bash "$L" status
check "status: not running exits 3" eval '[ $rc = 3 ] && has "not running"'

FAKE_DIE=1 run bash "$L" start
check "start: a server that exits while loading fails at once and shows the log tail" \
  eval '[ $rc = 1 ] && has "exited while starting" && has "fake: out of memory" && [ ! -e "$pidf" ] && [ ! -e "$envf" ]'

SECONDS=0
FAKE_NEVER_READY=1 run bash "$L" start
took=$SECONDS
check "start: a server that never gets healthy is stopped after the timeout" \
  eval '[ $rc = 1 ] && has "did not become ready" && [ "$took" -le 8 ] && [ "$(nservers)" = 0 ] && [ ! -e "$pidf" ]'

rm -f "$T/args"; touch "$T/healthy"
run bash "$L" start
check "start: another program answering on the port is refused, and nothing starts" \
  eval '[ $rc = 2 ] && has "port 8088 already answers" && [ ! -e "$T/args" ]'
rm -f "$T/healthy"

# A stale pid file: its process is gone (after a crash or wsl --shutdown).
mkdir -p "$T/qh/run"; sh -c 'exit 0' & dead=$!; wait "$dead"
echo "$dead" > "$pidf"; printf 'QWEN_PORT=8088\nQWEN_CTX=102400\n' > "$envf"
run bash "$L" status
check "status: a stale pid file means not running, and is cleaned up" \
  eval '[ $rc = 3 ] && has "not running" && [ ! -e "$pidf" ] && [ ! -e "$envf" ]'

# A reused pid: the pid file names a live process that is not llama-server.
sleep 60 & SLEEPER=$!
echo "$SLEEPER" > "$pidf"
run bash "$L" stop
check "stop: a pid that is not llama-server is never killed; the pid file is removed as stale" \
  eval '[ $rc = 0 ] && has stale && kill -0 "$SLEEPER" && [ ! -e "$pidf" ]'

# qwen_load_state
printf 'QWEN_PORT=9000\nQWEN_CTX=65536\n' > "$envf"
run bash -c '. "$1/qwen-lib.sh"; qwen_load_state; qwen_url; echo "ctx=$QWEN_CTX"' _ "$S"
check "qwen_load_state: the running server's port and context win over the defaults" \
  eval 'has "http://127.0.0.1:9000" && has "ctx=65536"'

exit $fail

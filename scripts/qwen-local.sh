#!/usr/bin/env bash
# Start, stop and check llama-server serving Qwen 3.8 27B on 127.0.0.1, all of it on the GPU
# (docs/5-research/2026-10-19-local-qwen-design.md; setup in docs/5-research/2026-10-19-local-qwen-notes.md).
#   qwen-local.sh start    start the server in the background; wait until it answers /health
#   qwen-local.sh stop     stop it (TERM, then KILL after 30 seconds)
#   qwen-local.sh status   exit 0 and print the URL when it runs, exit 3 when it does not
#   qwen-local.sh cmd      print the server command line, and run nothing
# Environment, besides qwen-lib.sh's QWEN_HOME, QWEN_PORT, QWEN_CTX and QWEN_ALIAS:
#   QWEN_LLAMA_SERVER   the binary ($QWEN_HOME/llama.cpp/build/bin/llama-server)
#   QWEN_MODEL          the GGUF file ($QWEN_HOME/models/model.gguf)
#   QWEN_EFFORT         reasoning effort: low (default), medium, xhigh, or off (no thinking)
#   QWEN_MTP_ARGS       the multi-token prediction flags, split on spaces; empty turns MTP off
#   QWEN_START_TIMEOUT  seconds to wait for /health (300: loading 17 GB takes a while)
# The log is $QWEN_HOME/logs/server.log; the previous one is kept as server.log.1.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=qwen-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/qwen-lib.sh"
usage() { echo "usage: qwen-local.sh start|stop|status|cmd" >&2; exit 2; }
[ $# -eq 1 ] || usage

bin="${QWEN_LLAMA_SERVER:-$QWEN_HOME/llama.cpp/build/bin/llama-server}"
model="${QWEN_MODEL:-$QWEN_HOME/models/model.gguf}"
effort="${QWEN_EFFORT:-low}"
mtp="${QWEN_MTP_ARGS-}"
timeout="${QWEN_START_TIMEOUT:-300}"
pidf="$QWEN_HOME/run/server.pid"
log="$QWEN_HOME/logs/server.log"

case "$effort" in
  off) kwargs='{"enable_thinking":false}' ;;
  low | medium | xhigh) kwargs="{\"reasoning_effort\":\"$effort\"}" ;;
  *) echo "QWEN_EFFORT is '$effort'; use one of low, medium, xhigh, off" >&2; exit 2 ;;
esac
args=(-m "$model" --alias "$QWEN_ALIAS" --host 127.0.0.1 --port "$QWEN_PORT" -ngl 999 -c "$QWEN_CTX"
  -fa on --cache-type-k q8_0 --cache-type-v q8_0 --parallel 1 --jinja
  --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --chat-template-kwargs "$kwargs")
# shellcheck disable=SC2206 # QWEN_MTP_ARGS is a list of flags, split on spaces on purpose
[ -z "$mtp" ] || args+=($mtp)

# running: print the pid of our llama-server, if the pid file names one that is alive. A pid file
# whose process is gone, or is some other program (the pid was reused), is stale and is removed.
running() {
  local pid
  [ -f "$pidf" ] || return 1
  pid="$(cat "$pidf")"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q llama-server; then
    echo "$pid"
    return 0
  fi
  echo "removing a stale pid file ($pidf: $pid)" >&2
  rm -f "$pidf" "$QWEN_STATE"
  return 1
}

quote() {
  local a out=()
  for a in "$@"; do
    if [[ "$a" =~ ^[A-Za-z0-9_./:=+,-]+$ ]]; then out+=("$a"); else out+=("'$a'"); fi
  done
  echo "${out[*]}"
}

stop_pid() {
  local pid="$1" i
  kill "$pid" 2>/dev/null || return 0
  for ((i = 0; i < 30; i++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 1
  done
  kill -KILL "$pid" 2>/dev/null || true
}

case "$1" in
  cmd) quote "$bin" "${args[@]}" ;;
  status)
    qwen_load_state
    if running >/dev/null; then echo "running on $(qwen_url)"; else echo "not running"; exit 3; fi
    ;;
  stop)
    if pid="$(running)"; then
      stop_pid "$pid"
      rm -f "$pidf" "$QWEN_STATE"
      echo "stopped"
    else
      echo "not running"
    fi
    ;;
  start)
    if running >/dev/null; then qwen_load_state; echo "already running on $(qwen_url)"; exit 0; fi
    [ -f "$model" ] || { echo "the model $model does not exist; see the setup in docs/5-research/2026-10-19-local-qwen-notes.md" >&2; exit 2; }
    [ -x "$bin" ] || { echo "llama-server $bin does not exist or is not executable" >&2; exit 2; }
    if qwen_healthy; then echo "port $QWEN_PORT already answers on $(qwen_url), and it is not our server; stop that program or set QWEN_PORT" >&2; exit 2; fi
    mkdir -p "$QWEN_HOME/run" "$QWEN_HOME/logs"
    [ ! -f "$log" ] || mv -f "$log" "$log.1"
    nohup "$bin" "${args[@]}" >"$log" 2>&1 &
    pid=$!
    echo "$pid" > "$pidf"
    printf 'QWEN_PORT=%s\nQWEN_CTX=%s\n' "$QWEN_PORT" "$QWEN_CTX" > "$QWEN_STATE"
    for ((i = 0; i < timeout; i++)); do
      if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$pidf" "$QWEN_STATE"
        echo "llama-server exited while starting; the end of $log:" >&2
        tail -n 20 "$log" >&2
        exit 1
      fi
      if qwen_healthy; then echo "ready on $(qwen_url) (pid $pid, log $log)"; exit 0; fi
      sleep 1
    done
    stop_pid "$pid"
    rm -f "$pidf" "$QWEN_STATE"
    echo "llama-server did not become ready within $timeout seconds; stopped it. The end of $log:" >&2
    tail -n 20 "$log" >&2
    exit 1
    ;;
  *) usage ;;
esac

#!/usr/bin/env bash
# Start, stop and check llama-server serving Qwen 3.8 27B on 127.0.0.1, all of it on the GPU
# (docs/5-research/2026-10-19-local-qwen-design.md; setup in docs/5-research/2026-10-19-local-qwen-notes.md).
#   qwen-local.sh start    start the server in the background; wait until it answers /health
#   qwen-local.sh stop     stop it (TERM, then KILL after 30 seconds)
#   qwen-local.sh status   exit 0 and print the URL when it runs, exit 3 when it does not
#   qwen-local.sh cmd      print the server command line, and run nothing
#   qwen-local.sh template save the running model's chat template, changed so that a system message
#                          after the first one is rendered instead of refused (Claude Code sends one,
#                          for hook context); start uses the saved file from then on
# Environment, besides qwen-lib.sh's QWEN_HOME, QWEN_PORT, QWEN_CTX and QWEN_ALIAS:
#   QWEN_LLAMA_SERVER   the binary ($QWEN_HOME/llama.cpp/build/bin/llama-server)
#   QWEN_MODEL          the GGUF file ($QWEN_HOME/models/model.gguf)
#   QWEN_EFFORT         reasoning effort: low (default), medium, xhigh, or off (no thinking)
#   QWEN_MTP_ARGS       the multi-token prediction flags, split on spaces; empty turns MTP off. The default
#                       drafts with $QWEN_HOME/models/mtp.gguf, all on the GPU
#   QWEN_CACHE_RAM      the most MiB of system RAM for llama-server's prompt cache (2048). Its own default,
#                       8192, grew past WSL's 12 GB memory cap in an agent session, and the kernel's
#                       out-of-memory killer stopped the server
#   QWEN_CTX_CHECKPOINTS  context checkpoints kept per slot (4). This hybrid model saves its recurrent
#                       state in system RAM at each checkpoint; the default, 32, grew the server by about
#                       4 GB over a long session. Fewer means more prompt re-reading after a rewind
#   QWEN_START_TIMEOUT  seconds to wait for /health (300: loading 17 GB takes a while)
#   QWEN_CHAT_TEMPLATE  the saved chat template ($QWEN_HOME/models/chat-template.jinja), used when it exists
# The log is $QWEN_HOME/logs/server.log; the previous one is kept as server.log.1.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=qwen-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/qwen-lib.sh"
usage() { echo "usage: qwen-local.sh start|stop|status|cmd|template" >&2; exit 2; }
[ $# -eq 1 ] || usage

bin="${QWEN_LLAMA_SERVER:-$QWEN_HOME/llama.cpp/build/bin/llama-server}"
model="${QWEN_MODEL:-$QWEN_HOME/models/model.gguf}"
effort="${QWEN_EFFORT:-low}"
mtp="${QWEN_MTP_ARGS---spec-type draft-mtp -md $QWEN_HOME/models/mtp.gguf -ngld all -ctkd q8_0 -ctvd q8_0}"
timeout="${QWEN_START_TIMEOUT:-300}"
tplf="${QWEN_CHAT_TEMPLATE:-$QWEN_HOME/models/chat-template.jinja}"
pidf="$QWEN_HOME/run/server.pid"
log="$QWEN_HOME/logs/server.log"

case "$effort" in
  off) reasoning=(--reasoning off) ;;
  low | medium | xhigh) reasoning=(--reasoning-effort "$effort") ;;
  *) echo "QWEN_EFFORT is '$effort'; use one of low, medium, xhigh, off" >&2; exit 2 ;;
esac
args=(-m "$model" --alias "$QWEN_ALIAS" --host 127.0.0.1 --port "$QWEN_PORT" -ngl 999 -c "$QWEN_CTX"
  -fa on --cache-type-k q8_0 --cache-type-v q8_0 --cache-ram "${QWEN_CACHE_RAM:-2048}"
  --ctx-checkpoints "${QWEN_CTX_CHECKPOINTS:-4}" --parallel 1 --jinja
  --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 "${reasoning[@]}")
[ ! -f "$tplf" ] || args+=(--chat-template-file "$tplf")
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

# The model's template refuses a system message after the first. This renders it as a system turn.
fix_template='
import json, sys
t = json.load(sys.stdin)["chat_template"]
old = "{{- raise_exception(\x27System message must be at the beginning.\x27) }}"
if t.count(old) != 1:
    sys.exit("did not find the line that refuses later system messages in the chat template; check the template by hand")
open(sys.argv[1], "w").write(t.replace(old, "{{- \x27<|im_start|>system\\n\x27 + content + \x27<|im_end|>\\n\x27 }}"))
'

case "$1" in
  cmd) quote "$bin" "${args[@]}" ;;
  template)
    qwen_require_server
    mkdir -p "$(dirname "$tplf")"
    if ! curl -fsS -m 10 "$(qwen_url)/props" | python3 -I -c "$fix_template" "$tplf.tmp"; then rm -f "$tplf.tmp"; exit 1; fi
    mv -f "$tplf.tmp" "$tplf"
    echo "saved $tplf; restart the server to use it: qwen-local.sh stop && qwen-local.sh start"
    ;;
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

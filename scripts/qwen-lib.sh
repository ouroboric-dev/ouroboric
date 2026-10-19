#!/usr/bin/env bash
# Shared defaults and helpers for the qwen-* scripts, which run Qwen 3.8 27B on the local GPU
# (docs/5-research/2026-10-19-local-qwen-design.md). Source this file; do not run it.
# The caller's values win over these defaults:
#   QWEN_HOME   model files, the llama.cpp build, logs and run state ($HOME/.local/share/qwen-local)
#   QWEN_PORT   the server's port on 127.0.0.1 (8088)
#   QWEN_CTX    the context size in tokens (102400)
#   QWEN_ALIAS  the model name the server answers to (qwen3.8-27b)
# QWEN_STATE, written by `qwen-local.sh start` and removed by `stop`, holds the running server's
# QWEN_PORT and QWEN_CTX, so that the launchers use the values the server really has.

QWEN_HOME="${QWEN_HOME:-$HOME/.local/share/qwen-local}"
QWEN_PORT="${QWEN_PORT:-8088}"
QWEN_CTX="${QWEN_CTX:-102400}"
QWEN_ALIAS="${QWEN_ALIAS:-qwen3.8-27b}"
QWEN_STATE="$QWEN_HOME/run/server.env"

# qwen_load_state: take QWEN_PORT and QWEN_CTX from the running server's state file, if there is one.
# The file is read as data, never sourced.
qwen_load_state() {
  local v
  [ -f "$QWEN_STATE" ] || return 0
  v="$(sed -n 's/^QWEN_PORT=\([0-9][0-9]*\)$/\1/p' "$QWEN_STATE" | head -n 1)"
  [ -z "$v" ] || QWEN_PORT="$v"
  v="$(sed -n 's/^QWEN_CTX=\([0-9][0-9]*\)$/\1/p' "$QWEN_STATE" | head -n 1)"
  [ -z "$v" ] || QWEN_CTX="$v"
}

qwen_url() { echo "http://127.0.0.1:$QWEN_PORT"; }

qwen_healthy() { curl -fsS -m 2 "$(qwen_url)/health" >/dev/null 2>&1; }

qwen_require_server() {
  qwen_load_state
  if ! qwen_healthy; then
    echo "the local model server is not running on $(qwen_url); start it with scripts/qwen-local.sh start" >&2
    exit 2
  fi
}

#!/usr/bin/env bash
# Shared defaults and helpers for the qwen-* scripts, which use the local model server
# (docs/5-research/2026-10-19-local-qwen-design.md; the server is scripts/ygg-models.sh, started from the
# operator's model list). Source this file; do not run it.
# The caller's values win over these defaults:
#   QWEN_HOME       logs and run state of the older measurement scripts ($HOME/.local/share/qwen-local)
#   QWEN_CTX        the context size in tokens (102400); keep it equal to `context` in the model list
#   QWEN_ALIAS      the model's name in the list (qwen3.8-27b); the name OpenCode and Claude Code ask for
#   QWEN_MODELS_SH  the script that reports the server (ygg-models.sh next to this file)
# The server's URL comes from `ygg-models.sh status`, which prints `running on <URL>, loaded: <name|none>`.

QWEN_HOME="${QWEN_HOME:-$HOME/.local/share/qwen-local}"
QWEN_CTX="${QWEN_CTX:-102400}"
QWEN_ALIAS="${QWEN_ALIAS:-qwen3.8-27b}"
QWEN_MODELS_SH="${QWEN_MODELS_SH:-$(dirname "${BASH_SOURCE[0]}")/ygg-models.sh}"

# qwen_url: print the running server's URL; exit 1 when it does not run.
qwen_url() {
  local line
  line="$("$QWEN_MODELS_SH" status 2>/dev/null)" || return 1
  case "$line" in "running on "*) ;; *) return 1 ;; esac
  line="${line#running on }"
  echo "${line%%,*}"
}

qwen_require_server() {
  if ! qwen_url >/dev/null; then
    echo "the local model server is not running; start it with scripts/ygg-models.sh start" >&2
    exit 2
  fi
}

#!/usr/bin/env bash
# Shared defaults and helpers for the qwen-* scripts, which use the local model server
# (docs/5-research/2026-10-19-local-qwen-design.md; the server is scripts/ygg-models.sh, started from the
# operator's model list). Source this file; do not run it.
# The caller's values win over these defaults:
#   QWEN_HOME       logs and run state of the older measurement scripts ($HOME/.local/share/qwen-local)
#   QWEN_CTX        the context size in tokens (102400); keep it equal to `context` in the model list
#   QWEN_ALIAS      the model's name in the list (qwen3.8-27b); the name OpenCode and Claude Code ask for
#   QWEN_MODELS_SH  the script that reports the server (ygg-models.sh next to this file)
#   QWEN_MODELS     the model list, passed as --models (ygg-models.sh's default list when unset)
# The server's URL comes from `ygg-models.sh status`, which prints `running on <URL>, loaded: <name|none>`.

QWEN_HOME="${QWEN_HOME:-$HOME/.local/share/qwen-local}"
QWEN_CTX="${QWEN_CTX:-102400}"
QWEN_ALIAS="${QWEN_ALIAS:-qwen3.8-27b}"
QWEN_MODELS_SH="${QWEN_MODELS_SH:-$(dirname "${BASH_SOURCE[0]}")/ygg-models.sh}"

# qwen_status: run `ygg-models.sh status` (with --models "$QWEN_MODELS" when set), print its line, pass its exit code on.
# Its stderr is not hidden: an engine that does not answer says why.
qwen_status() {
  local args=()
  [ -z "${QWEN_MODELS:-}" ] || args=(--models "$QWEN_MODELS")
  "$QWEN_MODELS_SH" "${args[@]}" status
}

# qwen_url: print the running server's URL; exit 1 when it does not run.
qwen_url() {
  local line
  line="$(qwen_status 2>/dev/null)" || return 1
  case "$line" in "running on "*) ;; *) return 1 ;; esac
  line="${line#running on }"
  echo "${line%%,*}"
}

# qwen_require_server: exit 2 with a hint when the server is not running (status exit 3), and exit 2 with the
# status script's own message when the check itself failed (the engine does not answer, the list is wrong).
qwen_require_server() {
  local rc=0
  qwen_status >/dev/null || rc=$?
  case "$rc" in
    0) ;;
    3) echo "the local model server is not running; start it with scripts/ygg-models.sh start" >&2; exit 2 ;;
    *) echo "the local model server could not be checked (ygg-models.sh status exit $rc; see above)" >&2; exit 2 ;;
  esac
}

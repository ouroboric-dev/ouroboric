#!/usr/bin/env bash
# Collect the evidence of one ygg run into one report you can paste, with secrets removed.
#   ygg-evidence.sh [--config FILE] [--output FILE] [--ygg COMMAND] [--clip] PROJECT [RUN_ID]
# PROJECT is the project folder. RUN_ID defaults to the newest run in PROJECT/.factory/runs.
# The report holds: ygg status, ygg doctor (with --config), the ledger lines that matter (node results,
# loop attempts, findings, retries, pauses, failures, sandboxes, realms and leaves, published documents,
# tasks) and, with --output, the end of a captured run output. A failed session shows up as a retry, run_paused, node_failed or run_failed line: paste
# those lines when a failure is not the agent's, so gleipnir/failure/failure.go can learn its words.
# Redaction: the value of every environment variable whose name has TOKEN, KEY, SECRET, PASSWORD or
# CREDENTIAL (8 characters or more) is replaced, and so are common token shapes (sk-..., ghp_...,
# github_pat_..., Bearer ...). Read the report before you paste it anyway.
# YGG_CMD (or --ygg) is the command that runs ygg; the default is `ygg` if it is on PATH, otherwise
# `go run ./cmd/ygg` in $YGG_ODIN (default: the odin folder next to this repo in the umbrella).
# --clip also copies the report to the Windows clipboard (clip.exe, in WSL).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config='' output='' clip=0 ygg="${YGG_CMD:-}"
usage() { echo "usage: ygg-evidence.sh [--config FILE] [--output FILE] [--ygg COMMAND] [--clip] PROJECT [RUN_ID]" >&2; exit 2; }
pos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --config) [ $# -ge 2 ] || usage; config="$2"; shift 2 ;;
    --output) [ $# -ge 2 ] || usage; output="$2"; shift 2 ;;
    --ygg) [ $# -ge 2 ] || usage; ygg="$2"; shift 2 ;;
    --clip) clip=1; shift ;;
    -h|--help) usage ;;
    -*) echo "ygg-evidence: unknown flag $1" >&2; usage ;;
    *) pos+=("$1"); shift ;;
  esac
done
[ "${#pos[@]}" -ge 1 ] && [ "${#pos[@]}" -le 2 ] || usage
project="$(cd "${pos[0]}" && pwd)" || { echo "ygg-evidence: no project folder ${pos[0]}" >&2; exit 2; }
runs="$project/.factory/runs"
run="${pos[1]:-}"
if [ -z "$run" ]; then
  [ -d "$runs" ] || { echo "ygg-evidence: $runs does not exist: no run yet" >&2; exit 2; }
  run="$(ls -1 "$runs" | sort | tail -n 1)"
  [ -n "$run" ] || { echo "ygg-evidence: $runs holds no run" >&2; exit 2; }
fi
ledger="$runs/$run/ledger.jsonl"
[ -f "$ledger" ] || { echo "ygg-evidence: no ledger at $ledger" >&2; exit 2; }
if [ -z "$ygg" ]; then
  if command -v ygg >/dev/null 2>&1; then
    ygg=ygg
  else
    odin="${YGG_ODIN:-$HERE/../../yggdrasil/odin}"
    ygg="cd '$odin' && go run ./cmd/ygg"
  fi
fi

# redact: read stdin, write stdout. The secret values come from this shell's environment.
redact() {
  python3 -I -c '
import os, re, sys
text = sys.stdin.read()
name = re.compile(r"TOKEN|KEY|SECRET|PASSWORD|CREDENTIAL", re.I)
vals = sorted({v for k, v in os.environ.items() if name.search(k) and len(v) >= 8}, key=len, reverse=True)
for v in vals:
    text = text.replace(v, "[REDACTED]")
for pat in (r"sk-[A-Za-z0-9_-]{16,}", r"gh[pousr]_[A-Za-z0-9]{20,}", r"github_pat_[A-Za-z0-9_]{20,}",
            r"(?i)bearer\s+[A-Za-z0-9._~+/=-]{16,}"):
    text = re.sub(pat, "[REDACTED]", text)
sys.stdout.write(text)
'
}

report() {
  echo "# ygg evidence: run $run"
  echo
  echo "## status"
  echo '```'
  (eval "$ygg status '$run' --project '$project'") 2>&1 || echo "(ygg status exited $?)"
  echo '```'
  if [ -n "$config" ]; then
    echo
    echo "## doctor"
    echo '```'
    (eval "$ygg doctor --project '$project' --config '$config'") 2>&1 || echo "(ygg doctor exited $?)"
    echo '```'
  fi
  echo
  echo "## ledger"
  echo '```'
  grep -E '"event": ?"(run_started|run_resumed|run_finished|run_failed|run_paused|node_finished|node_failed|loop_attempt|finding_raised|finding_closed|finding_reopened|retry|escalation|policy_violation|budget_warning|sandbox_up|sandbox_down|realm_loaded|repo_created|docs_published|tasks_ready|node_returned|task_started|task_done|task_blocked)"' "$ledger" || echo "(no matching ledger lines)"
  echo '```'
  if [ -n "$output" ]; then
    echo
    echo "## run output (last 80 lines)"
    echo '```'
    tail -n 80 "$output"
    echo '```'
  fi
}

text="$(report | redact)"
printf '%s\n' "$text"
if [ "$clip" -eq 1 ]; then
  if command -v clip.exe >/dev/null 2>&1; then printf '%s\n' "$text" | clip.exe; echo "(copied to the clipboard)" >&2
  else echo "ygg-evidence: --clip needs clip.exe (WSL); the report is above" >&2; fi
fi

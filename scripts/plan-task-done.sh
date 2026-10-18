#!/usr/bin/env bash
# Run a task's tests in its repo, and only if they pass, append the completion line to the ledger.
#   plan-task-done.sh WORKSPACE TASK REPO BASE -- COMMAND...
# The ledger is WORKSPACE/progress.md. The full output goes to WORKSPACE/task-<TASK>-tests.log and its
# tail is printed. A failing command records nothing and its exit code is this script's.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -ge 6 ] && [ "$5" = "--" ] || { echo "usage: plan-task-done.sh WORKSPACE TASK REPO BASE -- COMMAND..." >&2; exit 2; }
# shellcheck source-path=SCRIPTDIR source=plan-lib.sh
. "$HERE/plan-lib.sh"
plan_load "$1" || exit 2
id="$2" repo="$3" base="$4"
shift 5
dir="$PLAN_ROOT/$repo"
log="$PLAN_WS/task-$id-tests.log"
rc=0
(cd "$dir" && "$@") > "$log" 2>&1 || rc=$?
tail -n 8 "$log"
if [ "$rc" -ne 0 ]; then echo "plan-task-done: exit $rc; $id NOT recorded ($log)" >&2; exit "$rc"; fi
last="$(grep -v '^[[:space:]]*$' "$log" | tail -n 1 || true)"
line="Task $id: complete ($repo commits $(git -C "$dir" rev-parse --short=7 "$base")..$(git -C "$dir" rev-parse --short=7 HEAD), tests: (in $repo) $* → $last)"
printf '%s\n' "$line" >> "$PLAN_WS/progress.md"
echo "ledger: $line"

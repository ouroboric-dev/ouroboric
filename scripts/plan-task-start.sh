#!/usr/bin/env bash
# Write the brief of one plan task into its SDD workspace, and print where it is and the repo's BASE.
#   plan-task-start.sh WORKSPACE TASK REPO
# The brief is the plan's "### Task <TASK>:" section; a heading inside a code fence does not end it.
# BASE is REPO's HEAD, the commit the task's review range starts from. Use this in place of
# superpowers' task-start when the repo is not the current directory or the ids are not numbers.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -eq 3 ] || { echo "usage: plan-task-start.sh WORKSPACE TASK REPO" >&2; exit 2; }
# shellcheck source=plan-lib.sh
. "$HERE/plan-lib.sh"
plan_load "$1" || exit 2
id="$2" repo="$3"
out="$PLAN_WS/task-$id-brief.md"
awk -v id="$id" '
  /^```/ { infence = !infence }
  !infence && /^#+ / { intask = ($0 ~ ("^### Task " id "[:( ]")) }
  intask { print }
' "$PLAN_FILE" > "$out"
[ -s "$out" ] || { rm -f -- "$out"; echo "no task $id in the plan" >&2; exit 3; }
echo "brief: $out ($(wc -l < "$out") lines)"
echo "base: $(git -C "$PLAN_ROOT/$repo" rev-parse HEAD)"

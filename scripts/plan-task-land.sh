#!/usr/bin/env bash
# The landing checks of a Go task in its repo, then a comparison with the plan's reference commit.
#   plan-task-land.sh WORKSPACE TASK REPO
# Checks: gofmt, go vet, go test -race (the full output goes to WORKSPACE/task-<TASK>-land.log), and
# `reuse lint` through uvx. The exit code is 1 if any check fails. Then every changed or untracked
# file is compared with the same file at the task's commit in the reference workspace
# ($PLAN_REFERENCE, default WORKSPACE/reference, with a tasks.map). A difference is printed but does
# not fail the script: an executor may have a ruling for it.
# The reuse version is pinned by $PLAN_REUSE (default reuse==5.0.2).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -eq 3 ] || { echo "usage: plan-task-land.sh WORKSPACE TASK REPO" >&2; exit 2; }
# shellcheck source=plan-lib.sh
. "$HERE/plan-lib.sh"
plan_load "$1" || exit 2
id="$2" repo="$3"
cd "$PLAN_ROOT/$repo" || exit 2
bad=0
fmt="$(gofmt -l .)"
if [ -z "$fmt" ]; then echo "gofmt: clean"; else echo "gofmt: $fmt"; bad=1; fi
if go vet ./...; then echo "vet: clean"; else echo "vet: FAIL"; bad=1; fi
log="$PLAN_WS/task-$id-land.log"
if go test -race -count=1 ./... > "$log" 2>&1; then
  echo "test -race: ok ($(grep -c '^ok' "$log") packages)"
else
  echo "test -race: FAIL"; grep -E '^(--- FAIL|FAIL)' "$log"; bad=1
fi
if uvx -q --from "${PLAN_REUSE:-reuse==5.0.2}" reuse lint -q; then echo "reuse: ok"; else echo "reuse: FAIL"; bad=1; fi
ref_dir="${PLAN_REFERENCE:-$PLAN_WS/reference}"
ref="$(awk -v r="$repo" -v id="$id" '$1 == r && $3 == id { print $2 }' "$ref_dir/tasks.map" 2>/dev/null)"
if [ -z "$ref" ]; then echo "no reference commit for $id"; exit "$bad"; fi
git status --short
same=0
while read -r f; do
  if git -C "$ref_dir/$repo" show "$ref:$f" 2>/dev/null | cmp -s - "$f"; then
    same=$((same + 1))
  else
    echo "DIFFERS from reference $ref: $f"
  fi
done < <(git status --short --untracked-files=all | awk '{ print $2 }')
echo "same as reference $ref: $same file(s)"
exit "$bad"

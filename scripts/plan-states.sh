#!/usr/bin/env bash
# Test every commit of a range on its own, so each task's end state of a plan builds and passes alone.
#   plan-states.sh REFERENCE REPO BASE HEAD       e.g. plan-states.sh ./reference odin origin/main split3
# REFERENCE holds one git clone per repo. Each commit of BASE..HEAD in REPO gets a worktree in a fresh
# temporary directory, beside links to the other repos at their final state, as a pin of a merged
# sibling would give. Its go.work lists every repo with a go.mod. A commit passes if gofmt is clean and
# go vet and go test pass. Prints PASS or FAIL with the commit's subject, and exits 1 on any FAIL.
# The temporary directory (with the logs of failures) is kept when a commit failed, and removed otherwise.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -eq 4 ] || { echo "usage: plan-states.sh REFERENCE REPO BASE HEAD" >&2; exit 2; }
# shellcheck source-path=SCRIPTDIR source=plan-lib.sh
. "$HERE/plan-lib.sh"
ref="$(cd "$1" && pwd -P)" repo="$2" base="$3" head="$4"
unset GOWORK
W="$(mktemp -d)"
fail=0
for c in $(git -C "$ref/$repo" rev-list --reverse "$base..$head"); do
  d="$W/$c"
  mkdir -p "$d"
  git -C "$ref/$repo" worktree add -q --detach "$d/$repo" "$c"
  for other in "$ref"/*/go.mod; do
    name="$(basename "$(dirname "$other")")"
    [ "$name" = "$repo" ] || ln -s "$ref/$name" "$d/$name"
  done
  plan_gowork "$d"
  msg="$(git -C "$ref/$repo" log -1 --format=%s "$c")"
  if (cd "$d/$repo" && test -z "$(gofmt -l .)" && go vet ./... >/dev/null 2>&1 && go test -count=1 ./... > "$d/test.log" 2>&1); then
    echo "PASS $msg"
  else
    echo "FAIL $msg (log: $d/test.log)"; fail=1
  fi
  git -C "$ref/$repo" worktree remove --force "$d/$repo"
done
if [ "$fail" -eq 0 ]; then rm -rf -- "$W"; else echo "kept $W for the logs"; fi
exit "$fail"

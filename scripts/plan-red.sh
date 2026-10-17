#!/usr/bin/env bash
# For each task of a reference workspace, show the first failure its tests give before the code exists:
# the plan's "expected failure" for the step that runs the test first.
#   plan-red.sh REFERENCE
# REFERENCE holds one git clone per repo and a tasks.map ("<repo> <commit> <task id>" per line). For each
# task, the task commit's test files go onto its parent commit in a fresh worktree, and the first lines
# `go test` prints for their packages (apart from ok lines) are shown. Test files are files that match
# $PLAN_TEST_FILES, an extended regular expression (default: _test.go files, .test.ts(x) and .spec.ts(x) files, folders named *test, and
# testdata). The worktrees and their temporary directory are removed at the end.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -eq 1 ] || { echo "usage: plan-red.sh REFERENCE" >&2; exit 2; }
# shellcheck source=plan-lib.sh
. "$HERE/plan-lib.sh"
ref="$(cd "$1" && pwd -P)"
pattern="${PLAN_TEST_FILES:-_test\.go\$|\.(test|spec)\.tsx?\$|/[a-z]*test/|^testdata/}"
unset GOWORK
W="$(mktemp -d)"
trap 'rm -rf -- "$W"' EXIT
while read -r repo sha id _; do
  [ -n "$repo" ] || continue
  d="$W/$id"
  mkdir -p "$d"
  git -C "$ref/$repo" worktree add -q --detach "$d/$repo" "$sha^"
  for other in "$ref"/*/go.mod; do
    name="$(basename "$(dirname "$other")")"
    [ "$name" = "$repo" ] || ln -s "$ref/$name" "$d/$name"
  done
  plan_gowork "$d"
  tests="$(git -C "$ref/$repo" diff --name-only "$sha^" "$sha" | grep -E "$pattern" || true)"
  pkgs="$(echo "$tests" | grep '\.go$' | xargs -r -n1 dirname | sort -u | sed 's|^|./|' | tr '\n' ' ')"
  if [ -n "$tests" ]; then
    # shellcheck disable=SC2086  # file names without spaces, one word each
    (cd "$d/$repo" && git checkout -q "$sha" -- $tests)
  fi
  # shellcheck disable=SC2086
  out="$(cd "$d/$repo" && go test -count=1 $pkgs 2>&1 | grep -vE '^(ok|\?) ' | head -4)"
  printf '== %s (%s) pkgs: %s\n%s\n' "$id" "$repo" "$pkgs" "$out"
  git -C "$ref/$repo" worktree remove --force "$d/$repo"
done < "$ref/tasks.map"

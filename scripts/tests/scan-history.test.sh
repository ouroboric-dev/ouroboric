#!/usr/bin/env bash
# Tests for scan-history.sh with the real pinned gitleaks image.   scripts/tests/scan-history.test.sh
# Needs Podman. The fake token is built at run time, so no secret-shaped string is ever committed.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$HERE/../scan-history.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
commit() { git -C "$1" add -A && git -C "$1" -c user.name=Test -c user.email=test@example.invalid commit -qm "$2"; }

git init -q "$T/clean" && echo "hello" > "$T/clean/README.md" && commit "$T/clean" "readme"
git init -q "$T/leaky" && echo "hello" > "$T/leaky/README.md" && commit "$T/leaky" "readme"
# A GitHub token shape in an old commit, deleted in the next one: only a history scan finds it.
printf 'token = "%s%s"\n' ghp_ "$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 36)" > "$T/leaky/config.txt"
commit "$T/leaky" "add config"
git -C "$T/leaky" rm -q config.txt && commit "$T/leaky" "remove config"
mkdir "$T/notrepo"

"$SCAN" "$T/clean" > "$T/out" 2>&1; rc=$?
check "a clean repo prints clean and exits 0" bash -c "[ $rc = 0 ] && grep -qx 'clean $T/clean' '$T/out'"
"$SCAN" "$T/leaky" > "$T/out" 2>&1; rc=$?
check "a secret anywhere in history prints LEAKS and exits 1" bash -c "[ $rc = 1 ] && grep -qx 'LEAKS $T/leaky' '$T/out'"
check "the report never prints the secret" bash -c "! grep -q 'ghp_[A-Za-z0-9]\{36\}' '$T/out'"
"$SCAN" "$T/notrepo" > "$T/out" 2>&1; rc=$?
check "a folder that isn't a repo prints ERROR, not clean" bash -c "[ $rc = 1 ] && grep -qx 'ERROR $T/notrepo' '$T/out'"
"$SCAN" "$T/clean" "$T/leaky" "$T/clean" > "$T/out" 2>&1; rc=$?
check "several repos: each gets a line, and one leak fails the run" \
  bash -c "[ $rc = 1 ] && [ \$(grep -c '^clean ' '$T/out') = 2 ] && [ \$(grep -c '^LEAKS ' '$T/out') = 1 ]"

exit $fail

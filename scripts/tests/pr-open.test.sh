#!/usr/bin/env bash
# Tests for pr-open.sh against a fake as-bot.sh.   scripts/tests/pr-open.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
# The script runs from a copy next to a fake as-bot.sh, which logs each call and plays GitHub.
mkdir -p "$T/s"
cp "$HERE/../pr-open.sh" "$T/s/pr-open.sh"
cat > "$T/s/as-bot.sh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
case "$3 $4" in
  "pr create") echo "https://github.com/ouroboric-dev/gleipnir/pull/7" ;;
  "pr merge") if [ -n "${FAKE_MERGE_FAIL:-}" ]; then echo "GraphQL: Auto merge is not allowed for this repository" >&2; exit 1; fi ;;
esac
FAKE
chmod +x "$T/s/pr-open.sh" "$T/s/as-bot.sh"
export FAKE_LOG="$T/log"
U=https://github.com/ouroboric-dev/gleipnir/pull/7

: > "$FAKE_LOG"
out="$("$T/s/pr-open.sh" gleipnir --base main --head my-branch --title "A title" --body-file body.md 2>"$T/err")"; rc=$?
check "success: exit 0" [ "$rc" = 0 ]
check "success: the URL is printed" [ "$out" = "$U" ]
check "success: create, then arm, in order, both as the bot for the repo" \
  [ "$(cat "$FAKE_LOG")" = "gleipnir gh pr create --repo ouroboric-dev/gleipnir --base main --head my-branch --title A title --body-file body.md
gleipnir gh pr merge $U --auto --squash" ]
check "no admin bypass" bash -c "! grep -e '--admin' '$FAKE_LOG'"
check "the only merge call carries --auto" bash -c "[ \"\$(grep -c 'pr merge' '$FAKE_LOG')\" = 1 ] && grep 'pr merge' '$FAKE_LOG' | grep -q -e '--auto'"

: > "$FAKE_LOG"
out="$(FAKE_MERGE_FAIL=1 "$T/s/pr-open.sh" huldra --title t 2>"$T/err")"; rc=$?
check "arming fails: exit non-zero" [ "$rc" != 0 ]
check "arming fails: the message says the PR stays open and why" \
  bash -c "grep -q 'stays open' '$T/err' && grep -q 'auto-merge' '$T/err' && grep -q 'Auto merge is not allowed' '$T/err'"
check "arming fails: the URL is still printed" [ "$out" = "$U" ]
check "arming fails: nothing closes or deletes the PR" bash -c "! grep -e 'close' -e 'delete' '$FAKE_LOG'"

: > "$FAKE_LOG"
check "no repo: usage, exit 2, no call" bash -c "'$T/s/pr-open.sh' >/dev/null 2>&1; [ \$? = 2 ] && [ ! -s '$FAKE_LOG' ]"
exit "$fail"

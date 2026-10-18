#!/usr/bin/env bash
# Tests for rollout-ci.sh against local bare repos, a bot stub, fake-gh and setup and check stubs.   scripts/tests/rollout-ci.test.sh
# shellcheck disable=SC2329  # the helper functions are called by check
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RC="$HERE/../rollout-ci.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
TOKEN=ghp_FAKE_rollout_token
B="$T/git/ouroboric-dev"
export GIT_AUTHOR_NAME=Founder GIT_AUTHOR_EMAIL=founder@example.invalid GIT_COMMITTER_NAME=Founder GIT_COMMITTER_EMAIL=founder@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export ROLLOUT_ROOT="$T/root" ROLLOUT_GIT="file://$T/git"

# Stubs. Each logs its arguments and the bytes it read from stdin.
mkdir -p "$T/bin" "$T/prs" "$B" "$ROLLOUT_ROOT"
cp "$HERE/fake-gh" "$T/bin/gh" && chmod +x "$T/bin/gh"
# The git wrapper logs its arguments. When $T/move holds "<repo> <sha>", a push first moves that repo's
# remote base-ci to <sha>, as if someone else pushed between rollout-ci.sh's ls-remote and its push.
REAL_GIT="$(command -v git)"
cat > "$T/bin/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/git.log"
if [ -s "$T/move" ] && [[ " \$* " == *" push "* ]]; then
  read -r repo sha < "$T/move"
  "$REAL_GIT" -C "$B/\$repo.git" update-ref refs/heads/base-ci "\$sha"
  : > "$T/move"
fi
exec "$REAL_GIT" "\$@"
EOF
# The bot stub answers "gh pr list" from $T/prs/<repo> and "gh pr create" by writing it.
cat > "$T/bot" <<EOF
#!/usr/bin/env bash
jq -cn --arg stdin "\$(cat | wc -c)" '{args: \$ARGS.positional, stdin: \$stdin}' --args -- "\$@" >> "$T/bot.log"
repo="\$1"
case "\$3 \$4" in
  "pr list") cat "$T/prs/\$repo" 2>/dev/null; true ;;
  "pr create") echo "https://github.com/ouroboric-dev/\$repo/pull/1" | tee "$T/prs/\$repo" ;;
  *) exit 9 ;;
esac
EOF
cat > "$T/setup" <<EOF
#!/usr/bin/env bash
echo "\$* stdin=\$(cat | wc -c)" >> "$T/setup.log"
[ -z "\${SETUP_FAILS:-}" ] || exit 1
echo "set up \${!#}"
EOF
cat > "$T/check" <<EOF
#!/usr/bin/env bash
echo "\$* stdin=\$(cat | wc -c)" >> "$T/check.log"
if [ -n "\${CHECK_FAILS:-}" ]; then echo "FAIL \${!#} ruleset: stub"; exit 1; fi
echo "PASS \${!#} ruleset"
EOF
chmod +x "$T/bin/git" "$T/bot" "$T/setup" "$T/check"
export PATH="$T/bin:$PATH" ROLLOUT_BOT="$T/bot" ROLLOUT_SETUP="$T/setup" ROLLOUT_CHECK="$T/check"
: > "$T/bot.log"; : > "$T/setup.log"; : > "$T/check.log"; : > "$T/git.log"
# fake-gh answers the lint.yml lookups: a missing fixture is a 404.
export FAKE_GH_DIR="$T/gh"; mkdir -p "$FAKE_GH_DIR/GET" "$FAKE_GH_DIR/ERR"
lint() { echo "repos_$1_$2_contents_.github_workflows_lint.yml"; }

# prepare <repo> [branch]: a bare remote with one commit on main, and a clone of it under the root,
# with a base-ci branch holding one more commit unless the second argument is "none".
prepare() {
  local w="$ROLLOUT_ROOT/$1"
  git init -q --bare -b main "$B/$1.git"
  git init -q -b main "$w"
  echo "# $1" > "$w/README.md"
  git -C "$w" add README.md && git -C "$w" commit -q -m first
  git -C "$w" push -q "$B/$1.git" main
  [ "${2:-}" = none ] && return
  git -C "$w" checkout -q -b base-ci
  echo "ci" > "$w/ci.txt"
  git -C "$w" add ci.txt && git -C "$w" commit -q -m "Base CI"
}
for r in alpha beta epsilon zeta eta .github theta; do prepare "$r"; done
prepare gamma none
local_sha() { git -C "$ROLLOUT_ROOT/$1" rev-parse base-ci; }
remote_sha() { git -C "$B/$1.git" rev-parse -q --verify refs/heads/base-ci; }
creates() { jq -s '[.[]|select(.args[2:4]==["pr","create"])]|length' "$T/bot.log"; }
creates_for() { jq -s --arg r "$1" '[.[]|select(.args[0]==$r and .args[2:4]==["pr","create"])]|length' "$T/bot.log"; }
jqs() { jq -se "$@" >/dev/null; }
# no_token: the token is in no output, and in no argument to git, the bot or the stubs.
no_token() { ! grep -q "$TOKEN" "$T/out" "$T/err" "$T/git.log" "$T/bot.log" "$T/setup.log" "$T/check.log"; }
ack() { git -C "$ROLLOUT_ROOT/$1" rev-parse -q --verify refs/rollout-ci/base-ci; }
url() { echo "rollout-ci: $1: https://github.com/ouroboric-dev/$1/pull/1"; }

# push: two prepared repos
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push alpha beta <<<"typed input" > "$T/out" 2> "$T/err"; rc=$?
check "push two prepared repos: exit 0" [ "$rc" = 0 ]
check "push two prepared repos: both base-ci branches are on the remotes" \
  bash -c "[ '$(remote_sha alpha)' = '$(local_sha alpha)' ] && [ '$(remote_sha beta)' = '$(local_sha beta)' ]"
check "push two prepared repos: two PRs are opened through the bot" [ "$(creates)" = 2 ]
check "push two prepared repos: each PR is base main, head base-ci, titled 'Base CI: lint required'" \
  jqs 'map(select(.args[2:4]==["pr","create"])) | length == 2 and all(.args[4:12] == ["--repo","ouroboric-dev/"+.args[0],"--base","main","--head","base-ci","--title","Base CI: lint required"])' "$T/bot.log"
check "push two prepared repos: the PR body names the proposal and the protect step" \
  jqs 'map(select(.args[2:4]==["pr","create"])) | length == 2 and all(.args[12] == "--body" and (.args[13] | test("base-ci-rollout/proposal.md") and test("rollout-ci.sh protect")))' "$T/bot.log"
check "push two prepared repos: the bot looks for an open PR on base-ci first" \
  jqs 'map(select(.args[2:4]==["pr","list"])) | length == 2 and all(.args[4:] == ["--repo","ouroboric-dev/"+.args[0],"--head","base-ci","--state","open","--json","url","-q",".[0].url"])' "$T/bot.log"
check "push two prepared repos: both URLs are printed" [ "$(cat "$T/out")" = "$(url alpha; url beta)" ]
check "push: stdin never reaches the bot" jqs 'all(.stdin == "0")' "$T/bot.log"
check "push: the token never appears in any output or argument" no_token

# push again: nothing changed
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push alpha beta > "$T/out" 2> "$T/err"; rc=$?
check "push again with nothing changed: exit 0" [ "$rc" = 0 ]
check "push again with nothing changed: it prints up to date and the open PR's URL" \
  [ "$(cat "$T/out")" = "$(printf 'rollout-ci: alpha: up to date\n%s\nrollout-ci: beta: up to date\n%s' "$(url alpha)" "$(url beta)")" ]
check "push again with nothing changed: no second PR" [ "$(creates)" = 2 ]

# push .github: a repo name may start with a dot
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push .github > "$T/out" 2> "$T/err"; rc=$?
check "push .github: exit 0, base-ci is on the remote, and its PR URL is printed" \
  bash -c "[ $rc = 0 ] && [ '$(remote_sha .github)' = '$(local_sha .github)' ] && [ '$(cat "$T/out")' = '$(url .github)' ]"

# push with a global insteadOf that sends the org's URLs elsewhere (the founder's https-to-SSH rule):
# rollout-ci.sh's own rule is longer, so it wins, and the push still goes to $T/git with the token.
git init -q --bare -b main "$T/wrong/ouroboric-dev/theta.git"
printf '[url "file://%s/wrong/"]\n\tinsteadOf = file://%s/git/\n' "$T" "$T" > "$T/insteadof.gitconfig"
GIT_CONFIG_GLOBAL="$T/insteadof.gitconfig" GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push theta > "$T/out" 2> "$T/err"; rc=$?
check "push with a global insteadOf for the org's URLs: exit 0, base-ci lands on the real remote" \
  bash -c "[ $rc = 0 ] && [ '$(remote_sha theta)' = '$(local_sha theta)' ]"
check "push with a global insteadOf for the org's URLs: nothing reaches the rewritten remote" \
  bash -c "! git -C '$T/wrong/ouroboric-dev/theta.git' rev-parse -q --verify refs/heads/base-ci >/dev/null"

# push after a local rebase: the remote is updated, and the open PR is reused
git -C "$ROLLOUT_ROOT/alpha" commit -q --amend -m "Base CI, rebased"
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push alpha > "$T/out" 2> "$T/err"; rc=$?
check "push after a local rebase: exit 0" [ "$rc" = 0 ]
check "push after a local rebase: the remote is updated" [ "$(remote_sha alpha)" = "$(local_sha alpha)" ]
check "push after a local rebase: the open PR is reused, not a second one" \
  bash -c "[ '$(creates_for alpha)' = 1 ] && [ '$(cat "$T/out")' = '$(url alpha)' ]"
check "push after a local rebase: the token never appears in any output or argument" no_token

# push after a local rebase, while someone else moves the remote branch: the lease refuses it
git -C "$ROLLOUT_ROOT/alpha" commit -q --amend -m "Base CI, rebased again"
other="$(git -C "$B/alpha.git" commit-tree -p main -m "someone else" "main^{tree}")"
echo "alpha $other" > "$T/move"
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push alpha beta > "$T/out" 2> "$T/err"; rc=$?
check "push when someone else moved the remote branch: exit 1" [ "$rc" = 1 ]
check "push when someone else moved the remote branch: their commit is not overwritten" [ "$(remote_sha alpha)" = "$other" ]
check "push when someone else moved the remote branch: stderr names the repo" grep -q '^rollout-ci: alpha: ' "$T/err"
check "push when someone else moved the remote branch: no PR line for it, and the next repo still runs" \
  [ "$(cat "$T/out")" = "$(printf 'rollout-ci: beta: up to date\n%s' "$(url beta)")" ]
check "push when someone else moved the remote branch: no second PR" [ "$(creates_for alpha)" = 1 ]
check "push when someone else moved the remote branch: the token never appears in any output or argument" no_token

# push again: the remote moved between two runs, so push refuses until the move is folded in
git -C "$ROLLOUT_ROOT/alpha" commit -q --amend -m "Base CI, rebased a third time"
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push alpha > "$T/out" 2> "$T/err"; rc=$?
check "push when the remote moved between two runs: exit 1" [ "$rc" = 1 ]
check "push when the remote moved between two runs: their commit is not overwritten" [ "$(remote_sha alpha)" = "$other" ]
check "push when the remote moved between two runs: stderr names the repo, both SHAs and the acknowledgement" \
  grep -qx "rollout-ci: alpha: the remote base-ci moved: GitHub has $other, the last push was $(ack alpha); fold it in, then git update-ref refs/rollout-ci/base-ci $other" "$T/err"
check "push when the remote moved between two runs: nothing on stdout, no second PR" \
  bash -c "[ ! -s '$T/out' ] && [ '$(creates_for alpha)' = 1 ]"
git -C "$ROLLOUT_ROOT/alpha" fetch -q "$B/alpha.git" base-ci
git -C "$ROLLOUT_ROOT/alpha" rebase -q "$other"
git -C "$ROLLOUT_ROOT/alpha" update-ref refs/rollout-ci/base-ci "$other"
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push alpha > "$T/out" 2> "$T/err"; rc=$?
check "push after the move is acknowledged and the branch rebased: exit 0" [ "$rc" = 0 ]
check "push after the move is acknowledged: the remote is updated, and the last push is recorded" \
  bash -c "[ '$(remote_sha alpha)' = '$(local_sha alpha)' ] && [ '$(ack alpha)' = '$(local_sha alpha)' ]"
check "push after the move is acknowledged: the open PR is reused" \
  bash -c "[ '$(creates_for alpha)' = 1 ] && [ '$(cat "$T/out")' = '$(url alpha)' ]"

# push again: the remote branch was deleted between two runs
git -C "$B/beta.git" update-ref -d refs/heads/base-ci
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push beta > "$T/out" 2> "$T/err"; rc=$?
check "push when the remote branch was deleted between two runs: exit 1, it is not pushed again" \
  bash -c "[ $rc = 1 ] && ! git -C '$B/beta.git' rev-parse -q --verify refs/heads/base-ci >/dev/null"
check "push when the remote branch was deleted between two runs: the acknowledgement is to drop the record" \
  grep -qx "rollout-ci: beta: the remote base-ci moved: GitHub has none, the last push was $(ack beta); fold it in, then git update-ref -d refs/rollout-ci/base-ci" "$T/err"
git -C "$ROLLOUT_ROOT/beta" update-ref -d refs/rollout-ci/base-ci
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push beta > "$T/out" 2> "$T/err"; rc=$?
check "push after the deletion is acknowledged: exit 0, base-ci is back" \
  bash -c "[ $rc = 0 ] && [ '$(remote_sha beta)' = '$(local_sha beta)' ]"

# push after the merge: main holds lint.yml, so push does nothing
echo '{"name":"lint.yml"}' > "$FAKE_GH_DIR/GET/$(lint ouroboric-dev zeta).json"
echo 'HTTP 500' > "$FAKE_GH_DIR/ERR/$(lint ouroboric-dev eta)"
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push zeta > "$T/out" 2> "$T/err"; rc=$?
check "push when lint.yml is already on main: exit 0" [ "$rc" = 0 ]
check "push when lint.yml is already on main: it says to run protect" \
  [ "$(cat "$T/out")" = "rollout-ci: zeta: lint.yml is already on main; run protect" ]
check "push when lint.yml is already on main: nothing is pushed, no PR is touched" \
  bash -c "! git -C '$B/zeta.git' rev-parse -q --verify refs/heads/base-ci >/dev/null && jq -se 'all(.args[0] != \"zeta\")' '$T/bot.log' >/dev/null"
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push eta > "$T/out" 2> "$T/err"; rc=$?
check "push when the lint.yml lookup fails: exit 1, named, nothing pushed, no PR touched" \
  bash -c "[ $rc = 1 ] && grep -q '^rollout-ci: eta: .*HTTP 500' '$T/err' && ! git -C '$B/eta.git' rev-parse -q --verify refs/heads/base-ci >/dev/null && jq -se 'all(.args[0] != \"eta\")' '$T/bot.log' >/dev/null"
check "push: the token never appears in any output or argument" no_token

# a first push while someone else creates the remote branch: "must not exist" refuses it
echo "epsilon $(git -C "$B/epsilon.git" rev-parse main)" > "$T/move"
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push epsilon > "$T/out" 2> "$T/err"; rc=$?
check "a first push when someone else created the remote branch: exit 1" [ "$rc" = 1 ]
check "a first push when someone else created the remote branch: it is not overwritten" \
  [ "$(remote_sha epsilon)" = "$(git -C "$B/epsilon.git" rev-parse main)" ]
check "a first push when someone else created the remote branch: no PR is opened" [ "$(creates_for epsilon)" = 0 ]

# a repo without a local base-ci branch, and one with no clone at all
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev push gamma delta beta > "$T/out" 2> "$T/err"; rc=$?
check "a repo without a base-ci branch: exit 1" [ "$rc" = 1 ]
check "a repo without a base-ci branch: it is skipped and named" \
  [ "$(cat "$T/err")" = "$(printf 'rollout-ci: gamma: no base-ci branch in %s; skipped\nrollout-ci: delta: no base-ci branch in %s; skipped' "$ROLLOUT_ROOT/gamma" "$ROLLOUT_ROOT/delta")" ]
check "a repo without a base-ci branch: nothing is pushed for it" bash -c "! git -C '$B/gamma.git' rev-parse -q --verify refs/heads/base-ci >/dev/null"
check "a repo without a base-ci branch: the bot is never called for it" \
  jqs 'all(.args[0] != "gamma" and .args[0] != "delta")' "$T/bot.log"
check "a repo without a base-ci branch: the other repos still run" [ "$(cat "$T/out")" = "$(printf 'rollout-ci: beta: up to date\n%s' "$(url beta)")" ]

# usage
for args in "" "push" "pull alpha" "push -x" "push ../alpha" "push .." "push ." "protect .."; do
  # shellcheck disable=SC2086  # the words are the arguments
  GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev $args > "$T/out" 2> "$T/err"; rc=$?
  check "usage '$args': exit 2 and no output" bash -c "[ $rc = 2 ] && [ ! -s '$T/out' ]"
done
env -u GH_TOKEN "$RC" --org ouroboric-dev push alpha > "$T/out" 2> "$T/err"; rc=$?
check "no GH_TOKEN: exit 2" [ "$rc" = 2 ]

# protect: 200, 404 and 500
for r in alpha beta gamma; do echo '{}' > "$FAKE_GH_DIR/GET/repos_ouroboric-dev_$r.json"; done
echo '{}' > "$FAKE_GH_DIR/GET/repos_acme_alpha.json"
echo '{"name":"lint.yml"}' > "$FAKE_GH_DIR/GET/$(lint ouroboric-dev alpha).json"
echo 'HTTP 500' > "$FAKE_GH_DIR/ERR/$(lint ouroboric-dev gamma)"
CONFIG="$(cd "$HERE/../orgs" && pwd)/ouroboric-dev.json"
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev protect alpha beta gamma <<<"typed input" > "$T/out" 2> "$T/err"; rc=$?
check "protect 200, 404 and 500: exit 1" [ "$rc" = 1 ]
check "protect: setup runs only for the repo whose lint.yml is on main, with the config, and no stdin" \
  [ "$(cat "$T/setup.log")" = "--config $CONFIG alpha stdin=0" ]
check "protect: the ruleset check runs only for it, with no stdin" [ "$(cat "$T/check.log")" = "--check ruleset alpha stdin=0" ]
check "protect: it prints the setup and the check, and says not yet for the 404" \
  [ "$(cat "$T/out")" = "$(printf 'set up alpha\nPASS alpha ruleset\nrollout-ci: beta: lint.yml is not on main yet; not protected')" ]
check "protect: the 500 is printed and named" grep -q '^rollout-ci: gamma: .*HTTP 500' "$T/err"
check "protect: the token never appears in any output or argument" no_token

GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev protect nosuch beta > "$T/out" 2> "$T/err"; rc=$?
check "protect a repo that doesn't exist: exit 1, named" \
  bash -c "[ $rc = 1 ] && [ \"\$(cat '$T/err')\" = 'rollout-ci: nosuch: no such repo in ouroboric-dev' ]"
check "protect a repo that doesn't exist: setup never runs for it, the next repo still runs" \
  bash -c "! grep -q nosuch '$T/setup.log' && grep -q '^rollout-ci: beta: ' '$T/out'"

: > "$T/setup.log"; : > "$T/check.log"
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev protect alpha beta > "$T/out" 2> "$T/err"; rc=$?
check "protect 200 and 404 only: exit 0" [ "$rc" = 0 ]

: > "$T/setup.log"; : > "$T/check.log"
echo '{}' > "$FAKE_GH_DIR/GET/repos_ouroboric-dev_.github.json"
echo '{"name":"lint.yml"}' > "$FAKE_GH_DIR/GET/$(lint ouroboric-dev .github).json"
GH_TOKEN=$TOKEN "$RC" --org ouroboric-dev protect .github > "$T/out" 2> "$T/err"; rc=$?
check "protect .github: exit 0, setup and the ruleset check run for it" \
  bash -c "[ $rc = 0 ] && [ \"\$(cat '$T/setup.log')\" = '--config $CONFIG .github stdin=0' ] && [ \"\$(cat '$T/check.log')\" = '--check ruleset .github stdin=0' ]"

: > "$T/setup.log"; : > "$T/check.log"
GH_TOKEN=$TOKEN CHECK_FAILS=1 "$RC" --org ouroboric-dev protect alpha beta > "$T/out" 2> "$T/err"; rc=$?
check "protect when the ruleset check fails: exit 1" [ "$rc" = 1 ]
check "protect when the ruleset check fails: its result is printed" grep -qx 'FAIL alpha ruleset: stub' "$T/out"

: > "$T/setup.log"; : > "$T/check.log"
GH_TOKEN=$TOKEN SETUP_FAILS=1 "$RC" --org ouroboric-dev protect alpha > "$T/out" 2> "$T/err"; rc=$?
check "protect when setup fails: exit 1, no check, the repo is named" \
  bash -c "[ $rc = 1 ] && [ ! -s '$T/check.log' ] && grep -q '^rollout-ci: alpha: ' '$T/err'"

: > "$T/setup.log"; : > "$T/check.log"
jq '.org = "acme" | del(.licence_dir)' "$CONFIG" > "$T/acme.json"
echo '{"name":"lint.yml"}' > "$FAKE_GH_DIR/GET/$(lint acme alpha).json"
GH_TOKEN=$TOKEN "$RC" --config "$T/acme.json" protect alpha > "$T/out" 2> "$T/err"; rc=$?
check "protect in another org: setup runs, the ouroboric-dev ruleset check does not" \
  bash -c "[ $rc = 0 ] && [ \"\$(cat '$T/setup.log')\" = '--config $T/acme.json alpha stdin=0' ] && [ ! -s '$T/check.log' ]"

exit $fail

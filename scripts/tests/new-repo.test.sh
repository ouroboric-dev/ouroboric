#!/usr/bin/env bash
# Tests for new-repo.sh against a fake GitHub API, local bare repos and a setup stub.   scripts/tests/new-repo.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEW="$HERE/../new-repo.sh"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
posts() { grep -c '"method": "POST"' "$T/log"; }
TOKEN=ghp_FAKE_new_repo_token
B="$T/git/ouroboric-dev"

mkdir -p "$B"
: > "$T/log"
FAKE_GIT_ROOT="$T/git" python3 -I "$HERE/fake-github.py" "$T/log" "$T/port" &
for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
CREATE_REPO_API="http://127.0.0.1:$(cat "$T/port")"
CREATE_REPO_GIT="file://$T/git"
export CREATE_REPO_API CREATE_REPO_GIT
export GIT_AUTHOR_NAME=Founder GIT_AUTHOR_EMAIL=founder@example.invalid GIT_COMMITTER_NAME=Founder GIT_COMMITTER_EMAIL=founder@example.invalid

# The setup stub logs "<repo> <commits on main> <bytes read from stdin>".
cat > "$T/setup" <<EOF
#!/usr/bin/env bash
repo="\${!#}"
echo "\$repo \$(git -C "$B/\$repo.git" rev-list --count main) \$(cat | wc -c)" >> "$T/setup.log"
EOF
chmod +x "$T/setup"
export NEW_REPO_SETUP="$T/setup"
: > "$T/setup.log"

FILES='.github/workflows/lint.yml
.markdownlint.yaml
.pre-commit-config.yaml
LICENSE
LICENSES/AGPL-3.0-only.txt
LICENSES/CC-BY-4.0.txt
README.md
REUSE.toml'
PRBOT='https://github.com/organizations/ouroboric-dev/settings/installations, ouroboric-pr-bot, Configure, Repository access.'

GH_TOKEN=$TOKEN "$NEW" --org ouroboric-dev alpha "The alpha repo." beta "The beta repo." \
  <<<"typed input" > "$T/out" 2> "$T/err"; rc=$?
check "two new repos: exit 0" [ "$rc" = 0 ]
for r in alpha beta; do
  check "$r: main holds one commit" [ "$(git -C "$B/$r.git" rev-list --count main 2>/dev/null)" = 1 ]
  check "$r: the commit holds exactly the licences, the base CI and the README" \
    [ "$(git -C "$B/$r.git" ls-tree -r --name-only main 2>/dev/null)" = "$FILES" ]
  check "$r: the commit message is 'Licences and base CI'" \
    [ "$(git -C "$B/$r.git" log -1 --format=%s main 2>/dev/null)" = "Licences and base CI" ]
done
check "the README holds the repo's name and description" \
  [ "$(git -C "$B/alpha.git" show main:README.md 2>/dev/null)" = "$(printf '# alpha\n\nThe alpha repo.')" ]
check "setup runs once per repo, after its commit, with an empty stdin" \
  [ "$(cat "$T/setup.log")" = "$(printf 'alpha 1 0\nbeta 1 0')" ]
check "it prints the progress lines and the pr-bot message for each public repo" \
  [ "$(cat "$T/out")" = "$(printf 'new-repo: %s: created\nnew-repo: %s: first commit pushed\nnew-repo: %s: protected\nAdd %s to the pr-bot: %s\n' \
    alpha alpha alpha alpha "$PRBOT" beta beta beta beta "$PRBOT")" ]
check "the token is never printed" bash -c "! grep -q '$TOKEN' '$T/out' '$T/err'"

GH_TOKEN=$TOKEN "$NEW" --org ouroboric-dev --private gamma "The gamma repo." </dev/null > "$T/out" 2> "$T/err"; rc=$?
check "--private: exit 0" [ "$rc" = 0 ]
check "--private creates a private repo" \
  [ "$(grep '"method": "POST"' "$T/log" | tail -1 | jq -r '.body|fromjson|.visibility')" = private ]
check "--private: the 'Never add' message" grep -qx 'Never add gamma to the pr-bot: agents must not see this repo.' "$T/out"
check "--private: setup runs after the commit" grep -qx 'gamma 1 0' "$T/setup.log"

printf '{"org":"ouroboric-dev"}\n' > "$T/bad.json"
before="$(posts)"
GH_TOKEN=$TOKEN "$NEW" --org ouroboric-dev delta "D." taken "Exists already." > "$T/out" 2> "$T/err"; rc=$?
check "an existing repo: exit non-zero, nothing is created" bash -c "[ $rc != 0 ] && [ '$before' = $(posts) ]"
GH_TOKEN=$TOKEN "$NEW" --org ouroboric-dev --ci reuse,nope delta "D." >> "$T/out" 2>> "$T/err"; rc=$?
check "an unknown --ci piece: exit non-zero, nothing is created" bash -c "[ $rc != 0 ] && [ '$before' = $(posts) ]"
GH_TOKEN=$TOKEN "$NEW" --config "$T/bad.json" delta "D." >> "$T/out" 2>> "$T/err"; rc=$?
check "a bad config: exit non-zero, nothing is created" bash -c "[ $rc != 0 ] && [ '$before' = $(posts) ]"
env -u GH_TOKEN "$NEW" --org ouroboric-dev delta "D." >> "$T/out" 2>> "$T/err"; rc=$?
check "no GH_TOKEN: exit 2, nothing is created" bash -c "[ $rc = 2 ] && [ '$before' = $(posts) ]"
GH_TOKEN=$TOKEN "$NEW" --org ouroboric-dev --cl reuse widget "A widget." >> "$T/out" 2> "$T/err1"; rc=$?
check "an unknown option: exit 2, nothing is created" bash -c "[ $rc = 2 ] && [ '$before' = $(posts) ]"
check "an unknown option is named" grep -q 'unknown option: --cl' "$T/err1"
check "a refused run prints no progress" [ ! -s "$T/out" ]
check "a refused run never prints the token" bash -c "! grep -q '$TOKEN' '$T/out' '$T/err'"

GH_TOKEN=$TOKEN CREATE_REPO_GIT="file://$T/nowhere" "$NEW" --org ouroboric-dev epsilon "The epsilon repo." \
  </dev/null > "$T/out" 2> "$T/err"; rc=$?
check "a failed push: exit non-zero" [ "$rc" != 0 ]
check "a failed push: setup never runs" bash -c "! grep -q epsilon '$T/setup.log'"
check "a failed push: stderr names the repo and says it is not protected" grep -qx \
  'new-repo: epsilon was created, but the push failed. It is not protected and agents must not get it yet. Delete it, or push a first commit and run setup-repo.sh.' "$T/err"
check "a failed push: only the create is reported" [ "$(cat "$T/out")" = 'new-repo: epsilon: created' ]
check "a failed push never prints the token" bash -c "! grep -q '$TOKEN' '$T/out' '$T/err'"

printf '{"org":"ouroboric-dev","licence":"Apache-2.0","copyright":"Acme"}\n' > "$T/nolic.json"
printf '#!/bin/sh\nexit 1\n' > "$T/reuse-fails"
chmod +x "$T/reuse-fails"
before="$(posts)"
GH_TOKEN=$TOKEN ADD_LICENCES_REUSE="$T/reuse-fails" "$NEW" --config "$T/nolic.json" eta "The eta repo." \
  </dev/null > "$T/out" 2> "$T/err"; rc=$?
check "a failed licence download: exit non-zero" [ "$rc" != 0 ]
check "a failed licence download: nothing is created" [ "$before" = "$(posts)" ]
check "a failed licence download: stderr names the repo and the step" grep -q 'new-repo: eta: add-licences.sh failed' "$T/err"
check "a failed licence download: it never says was created" bash -c "! grep -q 'was created' '$T/err'"
check "a failed licence download: no progress" [ ! -s "$T/out" ]

printf '#!/bin/sh\nexit 7\n' > "$T/setup-fails"
chmod +x "$T/setup-fails"
GH_TOKEN=$TOKEN NEW_REPO_SETUP="$T/setup-fails" "$NEW" --org ouroboric-dev zeta "The zeta repo." \
  </dev/null > "$T/out" 2> "$T/err"; rc=$?
check "a failed setup: exit with its code" [ "$rc" = 7 ]
check "a failed setup: stderr says zeta is not protected" grep -qx \
  'new-repo: zeta was created, but setup-repo.sh failed. It is not protected and agents must not get it yet. Delete it, or push a first commit and run setup-repo.sh.' "$T/err"
check "a failed setup: it never says protected" bash -c "! grep -q protected '$T/out'"

exit $fail

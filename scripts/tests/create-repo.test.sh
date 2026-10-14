#!/usr/bin/env bash
# Tests for create-repo.sh against a fake GitHub API and local bare repos.   scripts/tests/create-repo.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE="$HERE/../create-repo.sh"
LICENSES="$HERE/../../LICENSES"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
posts() { grep -c '"method": "POST"' "$T/log"; }
bare() { echo "$T/git/ouroboric-dev/$1.git"; }

mkdir -p "$T/git/ouroboric-dev"
: > "$T/log"
FAKE_GIT_ROOT="$T/git" python3 -I "$HERE/fake-github.py" "$T/log" "$T/port" &
for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
# setup-repo.sh stand-in: records each repo and how many commits its main had when it ran.
cat > "$T/setup" <<EOF
#!/usr/bin/env bash
echo "\$1 \$(git --git-dir="$T/git/ouroboric-dev/\$1.git" rev-list --count main 2>/dev/null || echo 0)" >> "$T/setup.log"
EOF
chmod +x "$T/setup"
export CREATE_REPO_API="http://127.0.0.1:$(cat "$T/port")" CREATE_REPO_GIT="file://$T/git" CREATE_REPO_SETUP="$T/setup"
export GIT_AUTHOR_NAME=Founder GIT_AUTHOR_EMAIL=founder@example.invalid GIT_COMMITTER_NAME=Founder GIT_COMMITTER_EMAIL=founder@example.invalid

env -u GH_TOKEN "$CREATE" alpha "The alpha repo." 2> "$T/err"; rc=$?
check "without GH_TOKEN: exit 2, and nothing is called" bash -c "[ $rc = 2 ] && [ ! -s '$T/log' ]"
GH_TOKEN=ghp_FAKE "$CREATE" alpha 2>/dev/null; rc=$?
check "a repo without a description is refused" [ "$rc" = 2 ]
GH_TOKEN=ghp_FAKE "$CREATE" ../alpha "Bad." 2>/dev/null; rc=$?
check "a bad repo name is refused" [ "$rc" = 2 ]

GH_TOKEN=ghp_FAKE "$CREATE" alpha "The alpha repo." taken "Exists already." 2> "$T/err"; rc=$?
check "one existing repo stops the whole batch before anything is created" \
  bash -c "[ $rc = 2 ] && [ \$(grep -c '\"method\": \"POST\"' '$T/log') = 0 ] && grep -q taken '$T/err' && [ ! -e '$T/setup.log' ]"

GH_TOKEN=ghp_FAKE "$CREATE" alpha "The alpha repo." beta "The beta repo." > "$T/out" 2>&1; rc=$?
check "two new repos: exit 0" [ "$rc" = 0 ]
check "each repo is created public and empty, with issues, wiki and projects off" \
  [ "$(grep '"method": "POST"' "$T/log" | jq -cS '.body|fromjson' | tr '\n' ' ')" = '{"auto_init":false,"description":"The alpha repo.","has_issues":false,"has_projects":false,"has_wiki":false,"name":"alpha","visibility":"public"} {"auto_init":false,"description":"The beta repo.","has_issues":false,"has_projects":false,"has_wiki":false,"name":"beta","visibility":"public"} ' ]
check "every request carries the admin token" \
  bash -c "[ \"\$(jq -r .auth '$T/log' | sort -u)\" = 'Bearer ghp_FAKE' ]"
check "main holds one commit with only the licence files" \
  [ "$(git --git-dir="$(bare alpha)" ls-tree -r --name-only main | tr '\n' ' ')" = "LICENSE LICENSES/AGPL-3.0-only.txt LICENSES/CC-BY-4.0.txt REUSE.toml " ]
check "the commit is the only one on main" [ "$(git --git-dir="$(bare alpha)" rev-list --count main)" = 1 ]
check "LICENSE is the AGPL text" cmp -s <(git --git-dir="$(bare alpha)" show main:LICENSE) "$LICENSES/AGPL-3.0-only.txt"
git --git-dir="$(bare alpha)" show main:REUSE.toml > "$T/reuse.toml"
check "REUSE.toml makes docs, README.md and AGENTS.md CC-BY-4.0, and the rest AGPL" \
  bash -c "grep -q 'path = \[\"docs/\*\*\", \"README.md\", \"AGENTS.md\"\]' '$T/reuse.toml' && grep -q 'SPDX-License-Identifier = \"AGPL-3.0-only\"' '$T/reuse.toml'"
check "setup-repo.sh runs on each repo, after its first commit is pushed" \
  [ "$(tr '\n' ' ' < "$T/setup.log")" = "alpha 1 beta 1 " ]
check "the token is never printed" bash -c "! grep -q ghp_FAKE '$T/out'"
check "a public repo's output says to add it to the pr-bot" grep -q 'Add alpha to the pr-bot' "$T/out"

GH_TOKEN=ghp_FAKE "$CREATE" --private gamma "The gamma repo." > "$T/out" 2>&1; rc=$?
check "--private: exit 0" [ "$rc" = 0 ]
check "--private creates a private repo" \
  [ "$(grep '"method": "POST"' "$T/log" | tail -1 | jq -r '.body|fromjson|.visibility')" = private ]
check "--private says the pr-bot must never get the repo" grep -q 'Never add gamma to the pr-bot' "$T/out"
check "--private never says to add the repo to the pr-bot" bash -c "! grep -q 'Add gamma to the pr-bot' '$T/out'"

exit $fail

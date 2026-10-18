#!/usr/bin/env bash
# Tests for create-repo.sh against a fake GitHub API and local bare repos.   scripts/tests/create-repo.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE="$HERE/../create-repo.sh"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
posts() { grep -c '"method": "POST"' "$T/log"; }
logn() { wc -l < "$T/log"; }

mkdir -p "$T/git/acme"
printf '{"org":"acme","licence":"MIT","copyright":"Acme"}\n' > "$T/acme.json"
: > "$T/log"
FAKE_GIT_ROOT="$T/git" python3 -I "$HERE/fake-github.py" "$T/log" "$T/port" &
for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
CREATE_REPO_API="http://127.0.0.1:$(cat "$T/port")"
export CREATE_REPO_API
export GIT_AUTHOR_NAME=Founder GIT_AUTHOR_EMAIL=founder@example.invalid GIT_COMMITTER_NAME=Founder GIT_COMMITTER_EMAIL=founder@example.invalid

env -u GH_TOKEN "$CREATE" --config "$T/acme.json" alpha "The alpha repo." 2> "$T/err"; rc=$?
check "without GH_TOKEN: exit 2, and nothing is called" bash -c "[ $rc = 2 ] && [ ! -s '$T/log' ]"
GH_TOKEN=ghp_FAKE "$CREATE" --config "$T/acme.json" alpha 2>/dev/null; rc=$?
check "a repo without a description is refused" [ "$rc" = 2 ]
GH_TOKEN=ghp_FAKE "$CREATE" --config "$T/acme.json" ../alpha "Bad." 2>/dev/null; rc=$?
check "a bad repo name is refused" [ "$rc" = 2 ]

GH_TOKEN=ghp_FAKE "$CREATE" --config "$T/acme.json" alpha "The alpha repo." taken "Exists already." 2> "$T/err"; rc=$?
check "one existing repo stops the whole batch before anything is created" \
  bash -c "[ $rc = 2 ] && [ \$(grep -c '\"method\": \"POST\"' '$T/log') = 0 ] && grep -q taken '$T/err'"

GH_TOKEN=ghp_FAKE "$CREATE" --config "$T/acme.json" alpha "The alpha repo." beta "The beta repo." > "$T/out" 2>&1; rc=$?
check "two new repos: exit 0" [ "$rc" = 0 ]
check "each repo is created public and empty, with issues, wiki and projects off" \
  [ "$(grep '"method": "POST"' "$T/log" | jq -cS '.body|fromjson' | tr '\n' ' ')" = '{"auto_init":false,"description":"The alpha repo.","has_issues":false,"has_projects":false,"has_wiki":false,"name":"alpha","visibility":"public"} {"auto_init":false,"description":"The beta repo.","has_issues":false,"has_projects":false,"has_wiki":false,"name":"beta","visibility":"public"} ' ]
check "every request carries the admin token" \
  bash -c "[ \"\$(jq -r .auth '$T/log' | sort -u)\" = 'Bearer ghp_FAKE' ]"
check "the token is never printed" bash -c "! grep -q ghp_FAKE '$T/out'"
check "the repo is created in the config's org" \
  [ "$(grep '"method": "POST"' "$T/log" | jq -r .path | sort -u)" = /orgs/acme/repos ]
check "each created repo is a bare repo in the org" [ -d "$T/git/acme/alpha.git" ]
check "it prints created <repo> and nothing else" [ "$(cat "$T/out")" = "$(printf 'created alpha\ncreated beta')" ]

before="$(posts)"
GH_TOKEN=ghp_FAKE "$CREATE" --config "$T/acme.json" --check delta "D." > "$T/out" 2>&1; rc=$?
check "--check creates nothing" bash -c "[ $rc = 0 ] && [ ! -s '$T/out' ] && [ '$before' = $(posts) ]"

before="$(logn)"
GH_TOKEN=ghp_FAKE "$CREATE" --config "$T/acme.json" delta "D." delta "D again." 2> "$T/err"; rc=$?
check "a repo named twice is refused before any request" [ "$rc" = 2 ]
check "a repo named twice makes no request" [ "$before" = "$(logn)" ]
GH_TOKEN=ghp_FAKE "$CREATE" delta "D." 2>/dev/null; rc=$?
check "no --org or --config is refused" [ "$rc" = 2 ]
GH_TOKEN=ghp_FAKE "$CREATE" --config "$T/acme.json" --cl reuse delta "D." >/dev/null 2> "$T/err"; rc=$?
check "an unknown option is refused before any request, and named" \
  bash -c "[ $rc = 2 ] && [ '$before' = \$(wc -l < '$T/log') ] && grep -q 'unknown option: --cl' '$T/err'"
GH_TOKEN=ghp_FAKE "$CREATE" --config "$T/acme.json" delta "D." -epsilon "E." >/dev/null 2>&1; rc=$?
check "a repo name that starts with - is refused before any request" \
  bash -c "[ $rc = 2 ] && [ '$before' = \$(wc -l < '$T/log') ]"

GH_TOKEN=ghp_FAKE "$CREATE" --config "$T/acme.json" --private gamma "The gamma repo." > "$T/out" 2>&1; rc=$?
check "--private: exit 0" [ "$rc" = 0 ]
check "--private creates a private repo" \
  [ "$(grep '"method": "POST"' "$T/log" | tail -1 | jq -r '.body|fromjson|.visibility')" = private ]

exit $fail

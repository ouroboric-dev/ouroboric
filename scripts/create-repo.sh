#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Create new, empty repos in the org that a config names, or in a user's own account when the config
# has "owner": "user". Each repo has no commits and no settings beyond the visibility, so nothing in it
# is protected yet. new-repo.sh is the normal way to run this script: it adds the first commit and
# protects the repo. If any repo already exists, a name repeats or
# a description is bad, nothing is created. Stops at the first error. A description is one line, with
# no control characters and no leading or trailing spaces: new-repo.sh makes it the first paragraph of
# README.md.
# Founder-run: GH_TOKEN must hold the short-lived admin token, with Administration read and write
# (the pr-bot can't create repos). For a user config, the token is the user's own, and it must
# belong to the config's account, or nothing is created.
#   GH_TOKEN=... create-repo.sh (--org <name>|--config <path>) [--private] [--check] <repo> "<description>" [<repo> "<description>"]...
# --check runs every check, creates nothing and prints nothing. --private makes private repos, such as
# huldra, the hidden benchmark suite.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="${CREATE_REPO_API:-https://api.github.com}"
die() { echo "create-repo: $*" >&2; exit 2; }
# shellcheck source=repo-config.sh
. "$HERE/repo-config.sh"

repo_config_args "$@"
repo_config_load
[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN must hold the short-lived admin token"
visibility=public check=''
set -- "${RC_REST[@]}"
while [ $# -gt 0 ]; do
  case "$1" in
    --private) visibility=private ;;
    --check) check=1 ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
  shift
done
[ $# -ge 2 ] && [ $(($# % 2)) = 0 ] || die 'usage: create-repo.sh (--org <name>|--config <path>) [--private] [--check] <repo> "<description>" [<repo> "<description>"]...'
args=("$@")
T="$(mktemp -d)"
trap 'rm -rf -- "${T:?}"' EXIT

request() { # request METHOD PATH [JSON]: prints the HTTP status; the reply goes to $T/reply
  curl -sS -o "$T/reply" -w '%{http_code}' -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$GH_TOKEN") \
    -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
    ${3:+--data "$3"} "$API$2" || die "$1 $2: request failed"
}
message() { jq -r '.message? // empty' "$T/reply" 2>/dev/null; }

for ((i = 0; i < ${#args[@]}; i += 2)); do
  r="${args[i]}"
  [[ "$r" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] || die "bad repo name: $r"
  [ -n "${args[i + 1]}" ] || die "$r: the description is empty"
  # The description becomes the first paragraph of README.md: one line, no control characters, no
  # leading or trailing spaces.
  ok="$(jq -rn --arg d "${args[i + 1]}" '$d | (test("\\p{Cc}") or test("\\A\\s|\\s\\z")) | not')"
  [ "$ok" = true ] || die "$r: the description must be one line, with no control characters and no leading or trailing spaces"
  for ((j = 0; j < i; j += 2)); do [ "${args[j]}" != "$r" ] || die "$r is named twice"; done
done
# A user's repos are created on the token's own account, so the token must be the config's account.
create="/orgs/$RC_ORG/repos"
if [ "$RC_OWNER" = user ]; then
  code="$(request GET /user)"
  [ "$code" = 200 ] || die "can't tell whose token this is (HTTP $code); nothing was created"
  login="$(jq -r '.login // empty' "$T/reply")"
  [ "${login,,}" = "${RC_ORG,,}" ] || die "the token belongs to ${login:-no user}, not $RC_ORG; nothing was created"
  create=/user/repos
fi
for ((i = 0; i < ${#args[@]}; i += 2)); do
  r="${args[i]}"
  code="$(request GET "/repos/$RC_ORG/$r")"
  [ "$code" = 404 ] || die "$r: already exists or can't be checked (HTTP $code); nothing was created"
done
[ -z "$check" ] || exit 0

for ((i = 0; i < ${#args[@]}; i += 2)); do
  r="${args[i]}"
  body="$(jq -cn --arg n "$r" --arg d "${args[i + 1]}" --arg v "$visibility" \
    '{name: $n, description: $d, visibility: $v, auto_init: false, has_issues: false, has_wiki: false, has_projects: false}')"
  code="$(request POST "$create" "$body")"
  [ "$code" = 201 ] || die "$r: GitHub refused to create it (HTTP $code: $(message))"
  echo "created $r"
done

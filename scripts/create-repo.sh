#!/usr/bin/env bash
# Create new, empty public ouroboric-dev repos, ready for agents. Each repo gets a first commit that
# holds only the licence files, then setup-repo.sh's settings and protect-main ruleset, so agents
# only ever see a protected repo. If any repo already exists, nothing is created. Stops at the first
# error.
# Founder-run: GH_TOKEN must hold the short-lived admin token, with Administration and Contents read
# and write (the pr-bot can't create repos).
#   GH_TOKEN=... create-repo.sh [--private] <repo> "<description>" [<repo> "<description>"]...
# The pr-bot is installed on selected repos only. A public repo must then be added to it, which the
# output says how to do. --private makes private repos that the pr-bot must never get, such as huldra,
# the hidden benchmark suite.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORG="ouroboric-dev"
API="${CREATE_REPO_API:-https://api.github.com}"
GIT="${CREATE_REPO_GIT:-https://github.com}"
SETUP="${CREATE_REPO_SETUP:-$HERE/setup-repo.sh}"
LICENSES="$HERE/../LICENSES"
die() { echo "create-repo: $*" >&2; exit 2; }

[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN must hold the short-lived admin token"
visibility=public
if [ "${1:-}" = --private ]; then visibility=private; shift; fi
[ $# -ge 2 ] && [ $(($# % 2)) = 0 ] || die 'usage: create-repo.sh [--private] <repo> "<description>" [<repo> "<description>"]...'
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
  [[ "$r" =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]] || die "bad repo name: $r"
  [ -n "${args[i + 1]}" ] || die "$r: the description is empty"
  code="$(request GET "/repos/$ORG/$r")"
  [ "$code" = 404 ] || die "$r: already exists or can't be checked (HTTP $code); nothing was created"
done

for ((i = 0; i < ${#args[@]}; i += 2)); do
  r="${args[i]}"
  body="$(jq -cn --arg n "$r" --arg d "${args[i + 1]}" --arg v "$visibility" \
    '{name: $n, description: $d, visibility: $v, auto_init: false, has_issues: false, has_wiki: false, has_projects: false}')"
  code="$(request POST "/orgs/$ORG/repos" "$body")"
  [ "$code" = 201 ] || die "$r: GitHub refused to create it (HTTP $code: $(message))"

  w="$T/$r"
  git init -q -b main "$w"
  mkdir "$w/LICENSES"
  cp "$LICENSES/AGPL-3.0-only.txt" "$LICENSES/CC-BY-4.0.txt" "$w/LICENSES/"
  cp "$LICENSES/AGPL-3.0-only.txt" "$w/LICENSE"
  cat > "$w/REUSE.toml" <<'EOF'
version = 1

[[annotations]]
path = ["**"]
precedence = "closest"
SPDX-FileCopyrightText = "2026 Bruno Guilhermo de Barros Valério"
SPDX-License-Identifier = "AGPL-3.0-only"

[[annotations]]
path = ["docs/**", "README.md", "AGENTS.md"]
precedence = "closest"
SPDX-FileCopyrightText = "2026 Bruno Guilhermo de Barros Valério"
SPDX-License-Identifier = "CC-BY-4.0"
EOF
  git -C "$w" add LICENSE LICENSES/AGPL-3.0-only.txt LICENSES/CC-BY-4.0.txt REUSE.toml
  git -C "$w" commit -q -m "Licences"
  # The helper reads GH_TOKEN when git asks, so the token never appears in a command line.
  git -C "$w" -c credential.helper= \
    -c 'credential.helper=!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$GH_TOKEN"; }; f' \
    push -q "$GIT/$ORG/$r.git" main

  "$SETUP" "$r"
  echo "created $r"
  if [ "$visibility" = public ]; then
    echo "Add $r to the pr-bot: https://github.com/organizations/$ORG/settings/installations, ouroboric-pr-bot, Configure, Repository access."
  else
    echo "Never add $r to the pr-bot: agents must not see this repo."
  fi
done

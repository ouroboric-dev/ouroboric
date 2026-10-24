#!/usr/bin/env bash
# Open a pull request as ouroboric-pr-bot and arm GitHub auto-merge on it. The default way an agent
# opens a pull request. Everything runs through as-bot.sh, so the token lasts one hour and reaches
# only the named repo.
# Arming auto-merge is not merging: the PR still waits for a human's approval and the required checks,
# which the ruleset demands. This script never merges directly and never uses an admin bypass.
# If arming fails, such as on a repo with auto-merge off (huldra), the PR stays open, the script says
# why and exits 1. It never closes or deletes the PR.
# Prints the PR's URL. Agent-run.
#   pr-open.sh <repo> [gh pr create arguments...]
#   pr-open.sh gleipnir --base main --head my-branch --title "..." --body-file body.md
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORG="ouroboric-dev"
die() { echo "pr-open: $*" >&2; exit 2; }

[ $# -ge 1 ] || die "usage: pr-open.sh <repo> [gh pr create arguments...]"
repo="$1"; shift
[[ "$repo" =~ ^[A-Za-z0-9._-]+$ ]] || die "bad repo: $repo"

out="$("$HERE/as-bot.sh" "$repo" gh pr create --repo "$ORG/$repo" "$@")" || exit $?
url="$(printf '%s\n' "$out" | grep -Eo 'https://[^[:space:]]+/pull/[0-9]+' | tail -1 || true)"
[ -n "$url" ] || die "gh pr create printed no pull request URL: $out"
echo "$url"

if ! err="$("$HERE/as-bot.sh" "$repo" gh pr merge "$url" --auto --squash 2>&1)"; then
  {
    echo "pr-open: the PR stays open, but auto-merge is not armed: $url"
    echo "pr-open: $err"
    echo "pr-open: the repo may have auto-merge off, as huldra does; a human can merge it once approved"
  } >&2
  exit 1
fi

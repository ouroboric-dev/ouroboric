#!/usr/bin/env bash
# Open a pull request as ouroboric-pr-bot and arm GitHub auto-merge on it. The default way an agent
# opens a pull request. Everything runs through as-bot.sh, so the token lasts one hour and reaches
# only the named repo.
# Arming auto-merge is not merging: the PR still waits for a human's approval and the required checks,
# which the ruleset demands. This script never merges directly and never uses an admin bypass.
# If arming fails, such as on a repo with auto-merge off (huldra), the PR stays open, the script says
# why and exits 1. It never closes or deletes the PR.
# It arms auto-merge only when the PR's base is the repo's default branch, the one branch whose ruleset requires
# an approval. A stacked PR, whose base is another branch, stays open without auto-merge (exit 0): armed, it
# would merge into that branch with no human.
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

# The ruleset that requires a human's approval protects the default branch only. A PR stacked on another branch
# would merge there, with no human, the moment its checks pass: auto-merge is armed only when the base is the
# default branch.
base="$("$HERE/as-bot.sh" "$repo" gh pr view "$url" --repo "$ORG/$repo" --json baseRefName -q .baseRefName)" || exit $?
default="$("$HERE/as-bot.sh" "$repo" gh repo view "$ORG/$repo" --json defaultBranchRef -q .defaultBranchRef.name)" || exit $?
if [ -z "$base" ] || [ "$base" != "$default" ]; then
  {
    echo "pr-open: auto-merge is not armed: the base '$base' is not the default branch '$default', and no ruleset"
    echo "pr-open: requires an approval there. The PR stays open; a human merges it, or it retargets to $default"
  } >&2
  exit 0
fi

if ! err="$("$HERE/as-bot.sh" "$repo" gh pr merge "$url" --auto --squash 2>&1)"; then
  {
    echo "pr-open: the PR stays open, but auto-merge is not armed: $url"
    echo "pr-open: $err"
    echo "pr-open: the repo may have auto-merge off, as huldra does; a human can merge it once approved"
  } >&2
  exit 1
fi

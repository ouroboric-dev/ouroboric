#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Roll the base CI out to existing repos in the org that a config names, in two steps. An agent has
# prepared each repo's base-ci branch in a clone at $ROLLOUT_ROOT/<repo> (default: rollout/ beside the
# ouroboric checkout), with add-ci.sh --upgrade and the formatting fixes.
#   push:    pushes each local base-ci branch to GitHub, then opens its pull request as the pr-bot
#            (as-bot.sh), or prints the one already open. The founder pushes because the pr-bot can't
#            push .github/workflows/. Each push is recorded in the clone's refs/rollout-ci/base-ci. A
#            second run after a rebase updates the branch, with --force-with-lease on that record. If
#            base-ci moved on GitHub since the last push (a person's commit, "Update branch"), push
#            refuses that repo and prints both SHAs: fold the move into the local branch, then
#            acknowledge it with git update-ref refs/rollout-ci/base-ci <GitHub's SHA>, and run push
#            again. A repo whose main already holds lint.yml (the PR merged) is left alone. A repo
#            without a local base-ci branch is skipped and named.
#   protect: after the merge, runs setup-repo.sh on each repo whose main holds
#            .github/workflows/lint.yml, so lint becomes required, then (for ouroboric-dev)
#            check-repos.sh --check ruleset. A repo whose main has no lint.yml yet is named and left
#            alone, so lint is never required early. A repo that doesn't exist fails.
# Both are safe to run twice. Exit 0 when every repo succeeded or is not ready yet, 1 when any repo was
# skipped or failed, 2 for usage. It never prompts.
# Founder-run: GH_TOKEN must hold the same short-lived admin token as new-repo.sh (Contents and
# Workflows write for push, Administration for protect). Git gets it only through the credential
# helper; it is never printed. The pr-bot's key must be in place for as-bot.sh.
#   GH_TOKEN=... rollout-ci.sh (--org <name>|--config <path>) push|protect <repo>...
set -euo pipefail
exec </dev/null
export GIT_TERMINAL_PROMPT=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROLLOUT_ROOT:-$(cd "$HERE/../.." && pwd)/rollout}"
GIT="${ROLLOUT_GIT:-https://github.com}"
BOT="${ROLLOUT_BOT:-$HERE/as-bot.sh}"
SETUP="${ROLLOUT_SETUP:-$HERE/setup-repo.sh}"
CHECK="${ROLLOUT_CHECK:-$HERE/check-repos.sh}"
PROPOSAL="https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/changes/2026-10-18-base-ci-rollout/proposal.md"
die() { echo "rollout-ci: $*" >&2; exit 2; }
# shellcheck source=repo-config.sh
. "$HERE/repo-config.sh"

USAGE='usage: rollout-ci.sh (--org <name>|--config <path>) push|protect <repo>...'
[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN must hold the short-lived admin token"
repo_config_args "$@"
repo_config_load
set -- "${RC_REST[@]}"
[ $# -ge 2 ] || die "$USAGE"
mode="$1"
shift
case "$mode" in push | protect) ;; *) die "unknown mode: $mode; $USAGE" ;; esac
for r in "$@"; do
  # GitHub names: .github is one; . and .. are paths, and a leading - would read as an option.
  [[ "$r" =~ ^[A-Za-z0-9._-]+$ && "$r" != -* && "$r" != . && "$r" != .. ]] || die "bad repo name: $r"
done

# The helper reads GH_TOKEN when git asks, so the token never appears in a command line.
# shellcheck disable=SC2016  # $1 and $GH_TOKEN expand in the helper, not here
cred_git() {
  git -c credential.helper= \
    -c 'credential.helper=!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$GH_TOKEN"; }; f' \
    "$@"
}

# lookup PATH: GETs PATH with the founder's token. Returns 0 if it exists, 1 on a 404, and 2 on any
# other failure, with the error in $err.
err=''
lookup() {
  err="$(env -u GITHUB_TOKEN gh api "$1" --silent 2>&1 >/dev/null)" && return 0
  [[ "$err" == *"HTTP 404"* ]] && return 1
  return 2
}

# Only push writes refs/rollout-ci/base-ci: the SHA it last pushed, or no ref before the first push.
# It is the lease, so a move on GitHub since then is refused, not overwritten. (refs/remotes/ won't do:
# git fetch moves those.)
LAST=refs/rollout-ci/base-ci

push_one() {
  local r="$1" w="$ROOT/$1" remote="$GIT/$RC_ORG/$1.git" have want last fix url s=0
  if [ ! -e "$w/.git" ] || ! have="$(git -C "$w" rev-parse -q --verify refs/heads/base-ci)"; then
    echo "rollout-ci: $r: no base-ci branch in $w; skipped" >&2
    return 1
  fi
  # After the merge, base-ci is deleted on GitHub; pushing it again would open a second PR.
  lookup "repos/$RC_ORG/$r/contents/.github/workflows/lint.yml" || s=$?
  case "$s" in
    0) echo "rollout-ci: $r: lint.yml is already on main; run protect"; return 0 ;;
    2) echo "rollout-ci: $r: can't tell whether main holds lint.yml, so nothing is pushed: $err" >&2; return 1 ;;
  esac
  if ! want="$(cred_git -C "$w" ls-remote "$remote" refs/heads/base-ci)"; then
    echo "rollout-ci: $r: can't read base-ci from $remote" >&2
    return 1
  fi
  want="${want%%[[:space:]]*}"
  last="$(git -C "$w" rev-parse -q --verify "$LAST")" || last=''
  if [ "$want" = "$have" ]; then
    git -C "$w" update-ref "$LAST" "$have" || { echo "rollout-ci: $r: recording the last push failed" >&2; return 1; }
    echo "rollout-ci: $r: up to date"
  elif [ "$want" != "$last" ]; then
    if [ -n "$want" ]; then fix="git update-ref $LAST $want"; else fix="git update-ref -d $LAST"; fi
    echo "rollout-ci: $r: the remote base-ci moved: GitHub has ${want:-none}, the last push was ${last:-none}; fold it in, then $fix" >&2
    return 1
  # The lease is the last push, so a move racing this run is refused too. Empty means "must not exist".
  elif ! cred_git -C "$w" push -q --force-with-lease="refs/heads/base-ci:$last" "$remote" \
    refs/heads/base-ci:refs/heads/base-ci >&2; then
    echo "rollout-ci: $r: the push failed; if someone else moved base-ci on GitHub, fold it in and run push again" >&2
    return 1
  elif ! git -C "$w" update-ref "$LAST" "$have"; then
    echo "rollout-ci: $r: base-ci is pushed, but recording it failed; run git update-ref $LAST $have" >&2
    return 1
  fi
  if ! url="$("$BOT" "$r" gh pr list --repo "$RC_ORG/$r" --head base-ci --state open --json url -q '.[0].url')"; then
    echo "rollout-ci: $r: can't list its pull requests" >&2
    return 1
  fi
  if [ -z "$url" ] || [ "$url" = null ]; then
    if ! url="$("$BOT" "$r" gh pr create --repo "$RC_ORG/$r" --base main --head base-ci \
      --title "Base CI: lint required" \
      --body "This adds the base CI that new repos get, a full .pre-commit-config.yaml and .github/workflows/lint.yml, with the formatting fixes that make lint pass, as the base-CI rollout proposal says: $PROPOSAL. The founder pushed this branch, because the pr-bot can't push workflows. After this merges, the founder runs rollout-ci.sh protect $r, so lint becomes a required check.")"; then
      echo "rollout-ci: $r: base-ci is pushed, but opening the pull request failed; run push again" >&2
      return 1
    fi
  fi
  echo "rollout-ci: $r: $url"
}

protect_one() {
  local r="$1" s=0
  lookup "repos/$RC_ORG/$r" || s=$?
  case "$s" in
    1) echo "rollout-ci: $r: no such repo in $RC_ORG" >&2; return 1 ;;
    2) echo "rollout-ci: $r: can't read the repo, so it is not protected: $err" >&2; return 1 ;;
  esac
  s=0
  lookup "repos/$RC_ORG/$r/contents/.github/workflows/lint.yml" || s=$?
  if [ "$s" = 0 ]; then
    if ! "$SETUP" "${RC_FROM[@]}" "$r"; then
      echo "rollout-ci: $r: setup-repo.sh failed" >&2
      return 1
    fi
    [ "$RC_ORG" = ouroboric-dev ] || return 0
    "$CHECK" --check ruleset "$r"
  elif [ "$s" = 1 ]; then
    echo "rollout-ci: $r: lint.yml is not on main yet; not protected"
  else
    echo "rollout-ci: $r: can't tell whether main holds lint.yml, so it is not protected: $err" >&2
    return 1
  fi
}

rc=0
for r in "$@"; do
  if [ "$mode" = push ]; then push_one "$r" || rc=1; else protect_one "$r" || rc=1; fi
done
exit "$rc"

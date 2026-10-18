#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Roll the base CI out to existing repos in the org that a config names, in two steps. An agent has
# prepared each repo's base-ci branch in a clone at $ROLLOUT_ROOT/<repo> (default: rollout/ beside the
# ouroboric checkout), with add-ci.sh --upgrade and the formatting fixes.
#   push:    pushes each local base-ci branch to GitHub, then opens its pull request as the pr-bot
#            (as-bot.sh), or prints the one already open. The founder pushes because the pr-bot can't
#            push .github/workflows/. It reads the remote branch with git ls-remote and pushes only when
#            it differs, with --force-with-lease on that SHA, so a second run after a rebase updates the
#            branch, and a branch someone else moved in between is never overwritten. A repo without a
#            local base-ci branch is skipped and named.
#   protect: after the merge, runs setup-repo.sh on each repo whose main holds
#            .github/workflows/lint.yml, so lint becomes required, then (for ouroboric-dev)
#            check-repos.sh --check ruleset. A repo whose main has no lint.yml yet is named and left
#            alone, so lint is never required early.
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
  [[ "$r" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "bad repo name: $r"
done

# The helper reads GH_TOKEN when git asks, so the token never appears in a command line.
# shellcheck disable=SC2016  # $1 and $GH_TOKEN expand in the helper, not here
cred_git() {
  git -c credential.helper= \
    -c 'credential.helper=!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$GH_TOKEN"; }; f' \
    "$@"
}

push_one() {
  local r="$1" w="$ROOT/$1" remote="$GIT/$RC_ORG/$1.git" have want url
  if [ ! -e "$w/.git" ] || ! have="$(git -C "$w" rev-parse -q --verify refs/heads/base-ci)"; then
    echo "rollout-ci: $r: no base-ci branch in $w; skipped" >&2
    return 1
  fi
  if ! want="$(cred_git -C "$w" ls-remote "$remote" refs/heads/base-ci)"; then
    echo "rollout-ci: $r: can't read base-ci from $remote" >&2
    return 1
  fi
  want="${want%%[[:space:]]*}"
  if [ "$want" = "$have" ]; then
    echo "rollout-ci: $r: up to date"
  # An empty SHA in the lease means the remote branch must not exist yet.
  elif ! cred_git -C "$w" push -q --force-with-lease="refs/heads/base-ci:$want" "$remote" \
    refs/heads/base-ci:refs/heads/base-ci >&2; then
    echo "rollout-ci: $r: the push failed; if someone else moved base-ci on GitHub, find out why before you push again" >&2
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
  local r="$1" err
  if err="$(env -u GITHUB_TOKEN gh api "repos/$RC_ORG/$r/contents/.github/workflows/lint.yml" --silent 2>&1 >/dev/null)"; then
    if ! "$SETUP" "${RC_FROM[@]}" "$r"; then
      echo "rollout-ci: $r: setup-repo.sh failed" >&2
      return 1
    fi
    [ "$RC_ORG" = ouroboric-dev ] || return 0
    "$CHECK" --check ruleset "$r"
  elif [[ "$err" == *"HTTP 404"* ]]; then
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

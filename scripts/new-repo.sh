#!/usr/bin/env bash
# Create new repos in the org that a config names, each with a first commit and the required setup, so
# agents only ever see a protected repo. For each repo, in order: create-repo.sh creates it; a first
# commit holds README.md (the name and description), the licence files (add-licences.sh) and the base
# CI (add-ci.sh); the commit is pushed to main; setup-repo.sh protects it. Every check runs before the
# first repo is created: if any repo already exists, a name repeats, a --ci piece is unknown or the
# config is bad, nothing is created. Stops at the first error. It never prompts.
# Founder-run: GH_TOKEN must hold the admin token: fine-grained, short-lived, owned by the org,
# repository access "All repositories", with Administration, Contents and Workflows read and write
# (the pr-bot can't create repos).
#   GH_TOKEN=... new-repo.sh (--org <name>|--config <path>) [--private] [--ci <piece>,...] <repo> "<description>" [<repo> "<description>"]...
# --private makes private repos, such as huldra, the hidden benchmark suite. --ci replaces the
# config's base CI pieces. After each repo, it prints the config's after-create message, such as how
# to add a public repo to the pr-bot.
set -euo pipefail
exec </dev/null
export GIT_TERMINAL_PROMPT=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT="${CREATE_REPO_GIT:-https://github.com}"
SETUP="${NEW_REPO_SETUP:-$HERE/setup-repo.sh}"
die() { echo "new-repo: $*" >&2; exit 2; }
# shellcheck source=repo-config.sh
. "$HERE/repo-config.sh"

[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN must hold the short-lived admin token"
repo_config_args "$@"
repo_config_load
visibility=public private=() ci=()
set -- "${RC_REST[@]}"
while [ $# -gt 0 ]; do
  case "$1" in
    --private) visibility=private; private=(--private) ;;
    --ci) [ $# -ge 2 ] || die "--ci needs a value"; ci=(--ci "$2"); shift ;;
    *) break ;;
  esac
  shift
done
[ $# -ge 2 ] && [ $(($# % 2)) = 0 ] || die 'usage: new-repo.sh (--org <name>|--config <path>) [--private] [--ci <piece>,...] <repo> "<description>" [<repo> "<description>"]...'
args=("$@")

"$HERE/create-repo.sh" "${RC_FROM[@]}" ${private[@]+"${private[@]}"} --check "${args[@]}"
"$HERE/add-licences.sh" "${RC_FROM[@]}" --check
"$HERE/add-ci.sh" "${RC_FROM[@]}" ${ci[@]+"${ci[@]}"} --check

T="$(mktemp -d)"
trap 'rm -rf -- "${T:?}"' EXIT

# step NAME CMD...: runs CMD, its output on stderr. If it fails, says that repo $r is not protected
# and exits with CMD's code.
step() {
  local name="$1" rc=0
  shift
  "$@" >&2 || rc=$?
  [ "$rc" = 0 ] && return
  echo "new-repo: $r was created, but $name failed. It is not protected and agents must not get it yet. Delete it, or push a first commit and run setup-repo.sh." >&2
  exit "$rc"
}
readme() { printf '# %s\n\n%s\n' "$2" "$3" > "$1/README.md"; }
commit() { git -C "$1" add -A && git -C "$1" commit -q -m "Licences and base CI"; }

for ((i = 0; i < ${#args[@]}; i += 2)); do
  r="${args[i]}" d="${args[i + 1]}"
  "$HERE/create-repo.sh" "${RC_FROM[@]}" ${private[@]+"${private[@]}"} "$r" "$d" >/dev/null
  echo "new-repo: $r: created"

  w="$T/$r"
  step "git init" git init -q -b main "$w"
  step "writing the README" readme "$w" "$r" "$d"
  step "add-licences.sh" "$HERE/add-licences.sh" "${RC_FROM[@]}" "$w"
  step "add-ci.sh" "$HERE/add-ci.sh" "${RC_FROM[@]}" ${ci[@]+"${ci[@]}"} "$w"
  step "the first commit" commit "$w"
  # The helper reads GH_TOKEN when git asks, so the token never appears in a command line.
  # shellcheck disable=SC2016  # $1 and $GH_TOKEN expand in the helper, not here
  step "the push" git -C "$w" -c credential.helper= \
    -c 'credential.helper=!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$GH_TOKEN"; }; f' \
    push -q "$GIT/$RC_ORG/$r.git" main
  echo "new-repo: $r: first commit pushed"

  step "setup-repo.sh" "$SETUP" "${RC_FROM[@]}" "$r"
  echo "new-repo: $r: protected"
  repo_after_create "$visibility" "$r"
done

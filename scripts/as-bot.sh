#!/usr/bin/env bash
# Run a command as ouroboric-pr-bot, with a token that lasts one hour and reaches only the named repos.
# The command gets the token as GH_TOKEN, and git gets it for https://github.com only. SSH remotes
# are rewritten to HTTPS, so the SSH key is never used. This script never prints the token, and it
# is the only thing that reads the bot's key. Agent-run.
#   as-bot.sh [--read] <repo[,repo...]|all> <command...>     (all: read-only, every repo)
#   as-bot.sh yggdrasil git push -u origin my-branch
#   as-bot.sh yggdrasil gh pr create --title ... --body-file ...
#   as-bot.sh --read all scripts/check-repos.sh
set -euo pipefail
ORG="ouroboric-dev"
DIR="${PR_BOT_DIR:-$HOME/.config/ouroboric/pr-bot}"
API="${PR_BOT_API:-https://api.github.com}"
die() { echo "as-bot: $*" >&2; exit 2; }

read=false
perms='{"contents":"write","pull_requests":"write","metadata":"read"}'
if [ "${1:-}" = --read ]; then
  read=true; perms='{"contents":"read","pull_requests":"read","administration":"read","metadata":"read"}'; shift
fi
[ $# -ge 2 ] || die "usage: as-bot.sh [--read] <repo[,repo...]|all> <command...>"
repos="$1"; shift
if [ "$repos" = all ]; then
  $read || die "all needs --read: a write token names its repos"
else
  [[ "$repos" =~ ^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$ ]] || die "bad repo list: $repos"
fi
[ -r "$DIR/key.pem" ] && [ -r "$DIR/app.env" ] || die "no bot key in $DIR (the founder runs create-pr-bot.sh)"
client_id="$(sed -n 's/^PR_BOT_CLIENT_ID=//p' "$DIR/app.env")"
[ -n "$client_id" ] || die "no PR_BOT_CLIENT_ID in $DIR/app.env"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now="$(date +%s)"
jwt="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url).$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' \
  $((now - 60)) $((now + 540)) "$client_id" | b64url)"
jwt="$jwt.$(printf '%s' "$jwt" | openssl dgst -sha256 -sign "$DIR/key.pem" -binary | b64url)"

call() { # call METHOD PATH [JSON]: prints the reply; stops on any error with GitHub's message
  local out code
  out="$(curl -sS -X "$1" -w '\n%{http_code}' -H @<(printf 'Authorization: Bearer %s\n' "$jwt") \
    -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
    ${3:+--data "$3"} "$API$2")" || die "$1 $2: request failed"
  code="${out##*$'\n'}"; out="${out%$'\n'*}"
  [[ "$code" == 2* ]] || die "$1 $2: HTTP $code: $(jq -r '.message? // empty' <<<"$out" 2>/dev/null)"
  printf '%s' "$out"
}
inst="$(call GET "/orgs/$ORG/installation" | jq -r .id)"
# No repositories field means every repo the bot is installed on.
req="$(jq -cn --arg r "$repos" --argjson p "$perms" '{permissions: $p} + (if $r == "all" then {} else {repositories: ($r | split(","))} end)')"
token="$(call POST "/app/installations/$inst/access_tokens" "$req" | jq -r .token)"
[ -n "$token" ] && [ "$token" != null ] || die "GitHub's reply held no token"

# An empty helper drops every helper configured before it, so ours is the only one for github.com.
# Git applies the longest matching insteadOf, so the ouroboric-dev rule beats any global rule that
# sends https://github.com/ to SSH.
# shellcheck disable=SC2016  # the credential helper is single-quoted on purpose: git runs it, so $1 and $GH_TOKEN expand there
export GH_TOKEN="$token" GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=5 \
  GIT_CONFIG_KEY_0="credential.https://github.com.helper" GIT_CONFIG_VALUE_0="" \
  GIT_CONFIG_KEY_1="credential.https://github.com.helper" \
  GIT_CONFIG_VALUE_1='!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$GH_TOKEN"; }; f' \
  GIT_CONFIG_KEY_2="url.https://github.com/.insteadOf" GIT_CONFIG_VALUE_2="git@github.com:" \
  GIT_CONFIG_KEY_3="url.https://github.com/.insteadOf" GIT_CONFIG_VALUE_3="ssh://git@github.com/" \
  GIT_CONFIG_KEY_4="url.https://github.com/ouroboric-dev/.insteadOf" GIT_CONFIG_VALUE_4="https://github.com/ouroboric-dev/"
unset GITHUB_TOKEN
exec "$@"

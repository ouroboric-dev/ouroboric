#!/usr/bin/env bash
# Tests for as-bot.sh against a fake GitHub API.   scripts/tests/as-bot.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOT="$HERE/../as-bot.sh"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
b64d() { local s; s="$(tr '_-' '/+')"; while (( ${#s} % 4 )); do s+="="; done; openssl base64 -d -A <<<"$s"; }
last_body() { tail -1 "$T/log" | jq -cS '.body|fromjson'; }

mkdir -p "$T/bot" "$T/home"
openssl genrsa -out "$T/bot/key.pem" 2048 2>/dev/null
openssl rsa -in "$T/bot/key.pem" -pubout -out "$T/pub.pem" 2>/dev/null
echo "PR_BOT_CLIENT_ID=Iv1.test" > "$T/bot/app.env"
# A global credential helper that must never win for github.com.
printf '[credential]\n\thelper = "!f() { echo password=WRONG; }; f"\n' > "$T/home/.gitconfig"
FAKE_PEM="$T/bot/key.pem" python3 -I "$HERE/fake-github.py" "$T/log" "$T/port" &
for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
export HOME="$T/home" PR_BOT_DIR="$T/bot" PR_BOT_API="http://127.0.0.1:$(cat "$T/port")" GITHUB_TOKEN=must-be-removed

out="$("$BOT" yggdrasil sh -c 'printf "%s|%s" "$GH_TOKEN" "${GITHUB_TOKEN-unset}"')"
check "the command gets the token as GH_TOKEN, and GITHUB_TOKEN is removed" [ "$out" = "ghs_FAKE|unset" ]
check "the token is limited to the repo, with write permissions and no administration" \
  [ "$(last_body)" = '{"permissions":{"contents":"write","metadata":"read","pull_requests":"write"},"repositories":["yggdrasil"]}' ]

IFS=. read -r h p s < <(tail -1 "$T/log" | jq -r '.auth|sub("^Bearer ";"")')
check "the JWT header says RS256" [ "$(b64d <<<"$h" | jq -r .alg)" = RS256 ]
check "the JWT is issued by the client id and lives 10 minutes at most" \
  [ "$(b64d <<<"$p" | jq -r '"\(.iss) \(.exp - .iat)"')" = "Iv1.test 600" ]
b64d <<<"$s" > "$T/sig"
verify() { openssl dgst -sha256 -verify "$T/pub.pem" -signature "$T/sig" <(printf '%s.%s' "$h" "$p") >/dev/null; }
check "the JWT signature verifies with the bot's public key" verify

"$BOT" --read ouroboric,yggdrasil true
check "--read asks for read permissions, with administration read, for each listed repo" \
  [ "$(last_body)" = '{"permissions":{"administration":"read","contents":"read","metadata":"read","pull_requests":"read"},"repositories":["ouroboric","yggdrasil"]}' ]

"$BOT" --read all true
check "--read all asks for read permissions on every repo the bot is installed on" \
  [ "$(last_body)" = '{"permissions":{"administration":"read","contents":"read","metadata":"read","pull_requests":"read"}}' ]
n="$(wc -l < "$T/log")"
"$BOT" all touch "$T/ran" 2>/dev/null; rc=$?
check "all is refused without --read: write tokens name their repos" \
  bash -c "[ $rc = 2 ] && [ \$(wc -l < '$T/log') = $n ] && [ ! -e '$T/ran' ]"
"$BOT" .github true
check "a repo name may start with a dot, like .github" [ "$(last_body | jq -c .repositories)" = '[".github"]' ]

"$BOT" yggdrasil true > "$T/out" 2>&1
check "as-bot never prints the token" bash -c "! grep -q ghs_FAKE '$T/out'"

out="$(printf 'protocol=https\nhost=github.com\n\n' | "$BOT" yggdrasil git credential fill 2>/dev/null)"
check "git gets the token for github.com, ahead of other helpers" grep -qx 'password=ghs_FAKE' <<<"$out"
out="$(printf 'protocol=https\nhost=example.com\n\n' | "$BOT" yggdrasil git credential fill 2>/dev/null)"
check "git never sends the token to another host" bash -c "! grep -q ghs_FAKE <<<'$out'"
check "git uses HTTPS for SSH remotes, so the SSH key is never used" \
  [ "$("$BOT" yggdrasil git ls-remote --get-url git@github.com:ouroboric-dev/yggdrasil.git)" = https://github.com/ouroboric-dev/yggdrasil.git ]

n="$(wc -l < "$T/log")"
PR_BOT_DIR="$T/none" "$BOT" yggdrasil touch "$T/ran" 2> "$T/err"; rc=$?
check "without a key: exit 2, point to create-pr-bot.sh, call nothing" \
  bash -c "[ $rc = 2 ] && grep -q create-pr-bot.sh '$T/err' && [ \$(wc -l < '$T/log') = $n ] && [ ! -e '$T/ran' ]"
PR_BOT_API="$PR_BOT_API/nope" "$BOT" yggdrasil touch "$T/ran" 2> "$T/err"; rc=$?
check "a GitHub error stops before the command and shows GitHub's message" \
  bash -c "[ $rc != 0 ] && grep -q 'HTTP 404: Not Found' '$T/err' && [ ! -e '$T/ran' ]"
"$BOT" ../yggdrasil touch "$T/ran" 2>/dev/null; rc=$?
check "a bad repo name is refused" bash -c "[ $rc = 2 ] && [ ! -e '$T/ran' ]"

exit $fail

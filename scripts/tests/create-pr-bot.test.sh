#!/usr/bin/env bash
# Tests for create-pr-bot.sh against a fake GitHub API.   scripts/tests/create-pr-bot.test.sh
# The test plays the browser: it reads the local page, then follows GitHub's redirect back.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE="$HERE/../create-pr-bot.sh"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
status() { curl -s -o /dev/null -w '%{http_code}' "$1"; }
start() { # start DIR: runs create-pr-bot.sh in the background and waits for its page
  PORT=$((20000 + RANDOM % 20000))
  PR_BOT_DIR="$1" PR_BOT_PORT="$PORT" "$CREATE" > "$T/out" 2>&1 &
  PID=$!
  for _ in $(seq 50); do curl -s "http://127.0.0.1:$PORT/" > "$T/page" && return; sleep 0.1; done
}

openssl genrsa -out "$T/fake.pem" 2048 2>/dev/null
FAKE_PEM="$T/fake.pem" python3 -I "$HERE/fake-github.py" "$T/log" "$T/port" &
for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
export PR_BOT_API="http://127.0.0.1:$(cat "$T/port")" PR_BOT_WEB="http://example.invalid"

start "$T/cfg/pr-bot"
state="$(grep -o 'state=[0-9a-f]*' "$T/page" | head -1 | cut -d= -f2)"
check "the page posts to the org's new-App form with a random state" \
  grep -q "action=\"http://example.invalid/organizations/ouroboric-dev/settings/apps/new?state=[0-9a-f]\{32\}\"" "$T/page"
manifest="$(grep -o 'name="manifest" value="[^"]*"' "$T/page" | sed 's/^name="manifest" value="//; s/"$//' \
  | python3 -I -c 'import html,sys; print(html.unescape(sys.stdin.read()))')"
check "the manifest is the private pr-bot with the plan's permissions" \
  [ "$(jq -cS '[.name,.public,.default_permissions]' <<<"$manifest")" = '["ouroboric-pr-bot",false,{"administration":"read","contents":"write","metadata":"read","pull_requests":"write"}]' ]
check "the manifest sends the browser back to this script" \
  [ "$(jq -r .redirect_url <<<"$manifest")" = "http://localhost:$PORT/done" ]
check "a redirect with the wrong state is refused" [ "$(status "http://127.0.0.1:$PORT/done?code=good-code&state=bad")" = 400 ]
check "the script keeps waiting after a refused redirect" kill -0 "$PID"
check "the redirect with the right state is accepted" [ "$(status "http://127.0.0.1:$PORT/done?code=good-code&state=$state")" = 200 ]
wait "$PID"; rc=$?
check "the script exits 0" [ "$rc" = 0 ]
check "the key is saved" cmp -s "$T/fake.pem" "$T/cfg/pr-bot/key.pem"
check "the key and its folder are private" [ "$(stat -c %a "$T/cfg/pr-bot" "$T/cfg/pr-bot/key.pem" | tr '\n' ' ')" = "700 600 " ]
check "app.env holds the client id" grep -qx 'PR_BOT_CLIENT_ID=Iv1.test' "$T/cfg/pr-bot/app.env"
check "the output links the install page" grep -q 'http://example.invalid/apps/ouroboric-pr-bot/installations/new' "$T/out"
check "the output says selected repos only, never the hidden ones" \
  bash -c "grep -q 'Only select repositories' '$T/out' && grep -q 'never huldra' '$T/out' && ! grep -q 'all repositories' '$T/out'"
check "the output holds no key and no client secret" bash -c "! grep -q -e 'PRIVATE KEY' -e SECRET_CS '$T/out'"

PR_BOT_DIR="$T/cfg/pr-bot" PR_BOT_PORT=1 "$CREATE" > "$T/out" 2>&1; rc=$?
check "an existing key is never overwritten" bash -c "[ $rc = 2 ] && cmp -s '$T/fake.pem' '$T/cfg/pr-bot/key.pem'"

start "$T/cfg2/pr-bot"
state="$(grep -o 'state=[0-9a-f]*' "$T/page" | head -1 | cut -d= -f2)"
status "http://127.0.0.1:$PORT/done?code=bad-code&state=$state" >/dev/null
wait "$PID"; rc=$?
check "a code GitHub refuses fails and saves nothing" bash -c "[ $rc != 0 ] && [ ! -e '$T/cfg2/pr-bot/key.pem' ]"

exit $fail

#!/usr/bin/env bash
# Create the ouroboric-pr-bot GitHub App from pr-bot.json, and save its key for as-bot.sh.
# Founder-run, once. The script serves a local page that sends the manifest to GitHub. GitHub then
# sends the browser back with a one-time code, which the script trades for the App's key. The key
# is written to a private file and never printed.
#   create-pr-bot.sh      then open http://localhost:8719/ in a browser signed in as an org owner
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORG="ouroboric-dev"
DIR="${PR_BOT_DIR:-$HOME/.config/ouroboric/pr-bot}"
API="${PR_BOT_API:-https://api.github.com}"
WEB="${PR_BOT_WEB:-https://github.com}"
PORT="${PR_BOT_PORT:-8719}"
die() { echo "create-pr-bot: $*" >&2; exit 2; }
[ ! -e "$DIR/key.pem" ] || die "$DIR/key.pem exists; delete the old App and its key first"

state="$(openssl rand -hex 16)"
manifest="$(jq -c --arg u "http://localhost:$PORT/done" '.redirect_url = $u' "$HERE/pr-bot.json")"
# Serves the page that posts the manifest, then waits for GitHub's redirect and prints its code.
LISTENER='
import html, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
port, action, manifest, state = sys.argv[1:5]
class Handler(BaseHTTPRequestHandler):
    code = None
    def log_message(self, *args): pass
    def reply(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body.encode())
    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        q = urllib.parse.parse_qs(url.query)
        if url.path == "/":
            self.reply("<form method=\"post\" action=\"%s\"><input type=\"hidden\" name=\"manifest\" value=\"%s\">"
                       "<button>Create the App on GitHub</button></form><script>document.forms[0].submit()</script>"
                       % (html.escape(action), html.escape(manifest)))
        elif url.path == "/done" and q.get("state") == [state] and q.get("code"):
            Handler.code = q["code"][0]
            self.reply("Done. Go back to the terminal.")
        else:
            self.send_error(400)
server = HTTPServer(("127.0.0.1", int(port)), Handler)
while Handler.code is None:
    server.handle_request()
print(Handler.code)
'
echo "Open http://localhost:$PORT/ in a browser signed in to GitHub as an owner of $ORG."
code="$(python3 -I -c "$LISTENER" "$PORT" "$WEB/organizations/$ORG/settings/apps/new?state=$state" "$manifest" "$state")"
[[ "$code" =~ ^[A-Za-z0-9_-]+$ ]] || die "GitHub sent back an unexpected code"

app="$(curl -fsS -X POST -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
  "$API/app-manifests/$code/conversions")" || die "GitHub refused the code (it works once, within an hour)"
printf '%s' "$app" | jq -e '.pem | startswith("-----BEGIN")' >/dev/null || die "GitHub's reply held no key"
umask 077
mkdir -p "$DIR"
chmod 700 "$DIR"
printf '%s' "$app" | jq -j .pem > "$DIR/key.pem"
printf '%s' "$app" | jq -r '"PR_BOT_CLIENT_ID=\(.client_id)\nPR_BOT_APP_ID=\(.id)\nPR_BOT_SLUG=\(.slug)"' > "$DIR/app.env"
slug="$(printf '%s' "$app" | jq -r .slug)"
echo "Saved the bot's key in $DIR."
echo "Now install the App on $ORG, for all repositories: $WEB/apps/$slug/installations/new"

# Fake GitHub API for the script tests. Logs each request to LOG as one JSON line.
#   python3 -I fake-github.py LOG PORTFILE      (FAKE_PEM: the key the manifest conversion returns)
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

log, portfile = sys.argv[1:3]


def routes():
    return {
        ("GET", "/orgs/ouroboric-dev/installation"): (200, {"id": 42}),
        ("POST", "/app/installations/42/access_tokens"):
            (201, {"token": "ghs_FAKE", "expires_at": "2099-01-01T00:00:00Z"}),
        ("POST", "/app-manifests/good-code/conversions"):
            (201, {"id": 7, "slug": "ouroboric-pr-bot", "client_id": "Iv1.test",
                   "client_secret": "SECRET_CS", "webhook_secret": None,
                   "pem": open(os.environ["FAKE_PEM"]).read()}),
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def handle_any(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode() if n else ""
        with open(log, "a") as f:
            f.write(json.dumps({"method": self.command, "path": self.path,
                                "auth": self.headers.get("Authorization", ""), "body": body}) + "\n")
        code, obj = routes().get((self.command, self.path), (404, {"message": "Not Found"}))
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = handle_any


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(portfile, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()

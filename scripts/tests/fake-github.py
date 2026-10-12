# Fake GitHub API for the script tests. Logs each request to LOG as one JSON line.
#   python3 -I fake-github.py LOG PORTFILE
# FAKE_PEM: the key the manifest conversion returns. FAKE_GIT_ROOT: where a created repo gets its
# bare git repo, so a test can push to file://$FAKE_GIT_ROOT/<org>/<repo>.git.
import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

log, portfile = sys.argv[1:3]
repos = {"taken"}  # repos that already exist in ouroboric-dev


def repo_routes(method, path, body):
    prefix = "/repos/ouroboric-dev/"
    if method == "GET" and path.startswith(prefix):
        return (200, {"name": path[len(prefix):]}) if path[len(prefix):] in repos else None
    if method == "POST" and path == "/orgs/ouroboric-dev/repos":
        name = json.loads(body)["name"]
        if name in repos:
            return 422, {"message": "Repository creation failed."}
        repos.add(name)
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main",
                        os.path.join(os.environ["FAKE_GIT_ROOT"], "ouroboric-dev", name + ".git")], check=True)
        return 201, {"name": name}
    return None


def routes():
    return {
        ("GET", "/orgs/ouroboric-dev/installation"): (200, {"id": 42}),
        ("POST", "/app/installations/42/access_tokens"):
            (201, {"token": "ghs_FAKE", "expires_at": "2099-01-01T00:00:00Z"}),
        ("POST", "/app-manifests/good-code/conversions"):
            (201, {"id": 7, "slug": "ouroboric-pr-bot", "client_id": "Iv1.test",
                   "client_secret": "SECRET_CS", "webhook_secret": None,
                   "pem": open(os.environ["FAKE_PEM"]).read() if "FAKE_PEM" in os.environ else ""}),
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
        code, obj = repo_routes(self.command, self.path, body) \
            or routes().get((self.command, self.path), (404, {"message": "Not Found"}))
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

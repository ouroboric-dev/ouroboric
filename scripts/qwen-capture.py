#!/usr/bin/env python3
# A stand-in model server that records what a coding agent sends, for debugging the local Qwen setup
# (docs/5-research/2026-10-19-local-qwen-notes.md): it found Claude Code's mid-conversation system message
# and OpenCode's ignored config. Run it as `python3 -I`.
#   qwen-capture.py PORT OUTDIR
# It listens on 127.0.0.1:PORT and saves each POST body to OUTDIR/<nn>-<path>.json, numbered from 00.
# Each POST gets HTTP 500 with an API error, so the agent stops instead of waiting; a GET (a health check)
# gets 200. Point the agent at it, for example ANTHROPIC_BASE_URL=http://127.0.0.1:PORT, or an OpenCode
# provider baseURL of http://127.0.0.1:PORT/v1. Stop it with Ctrl-C.
import http.server
import itertools
import os
import sys

if len(sys.argv) != 3:
    sys.exit("usage: qwen-capture.py PORT OUTDIR")
port, out = int(sys.argv[1]), sys.argv[2]
os.makedirs(out, exist_ok=True)
seq = itertools.count()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        name = self.path.split("?")[0].strip("/").replace("/", "_") or "root"
        path = os.path.join(out, f"{next(seq):02d}-{name}.json")
        with open(path, "wb") as f:
            f.write(body)
        print(f"saved {path}", flush=True)
        data = b'{"type": "error", "error": {"type": "api_error", "message": "captured by qwen-capture.py"}}'
        self.send_response(500)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.send_response(200)
        self.send_header("content-length", "2")
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()

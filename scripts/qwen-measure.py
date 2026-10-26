#!/usr/bin/env python3
# Measure the local Qwen server (docs/5-research/2026-10-19-local-qwen-notes.md, "Measurements"). Every
# figure is the server's own: the timings in each /v1/chat/completions answer. Run it as `python3 -I`.
#   qwen-measure.py speed [--runs N] [--max-tokens M] PROMPT_FILE
#       N requests (3) with the prompt; one line per run, then the median decode and prompt speeds
#   qwen-measure.py prompt --tokens N [--question Q] --out FILE GLOB...
#       write a prompt of about N tokens, counted by the server's /tokenize: the files the globs match
#       (** allowed), each headed "// FILE <path>", repeated as needed, then the question
#   qwen-measure.py growth [--turns N] [--chunk C] --pid PID SOURCE_FILE
#       a conversation that grows by C characters (11000, about 3K tokens) of SOURCE_FILE per turn, for N
#       turns (20); after each, the context size and the resident memory of process PID (llama-server)
# QWEN_URL is the server (http://127.0.0.1:8088).
import argparse
import glob
import json
import os
import statistics
import sys
import time
import urllib.error
import urllib.request

URL = os.environ.get("QWEN_URL", "http://127.0.0.1:8088")


def post(path, body, timeout=1800):
    req = urllib.request.Request(URL + path, json.dumps(body).encode(), {"content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)
    except (urllib.error.URLError, ConnectionError) as e:
        sys.exit(f"the local model server does not answer on {URL} ({e}); start it with scripts/ygg-models.sh start")


def ntokens(text):
    return len(post("/tokenize", {"content": text})["tokens"])


def speed(a):
    prompt = open(a.prompt_file).read()
    rows = []
    for i in range(a.runs):
        t0 = time.time()
        r = post("/v1/chat/completions", {"model": "q", "max_tokens": a.max_tokens,
                                          "messages": [{"role": "user", "content": prompt}]})
        t, m = r["timings"], r["choices"][0]["message"]
        rows.append(t)
        print(f"run {i + 1}: prompt {t['prompt_n']} tokens at {t['prompt_per_second']:.0f} tokens/s"
              f" | decode {t['predicted_per_second']:.1f} tokens/s ({t['predicted_n']} tokens)"
              f" | draft {t.get('draft_n_accepted', '-')}/{t.get('draft_n', '-')}"
              f" | reasoning {len(m.get('reasoning_content') or '')} chars | wall {time.time() - t0:.1f}s", flush=True)
    print(f"median decode {statistics.median(t['predicted_per_second'] for t in rows):.1f} tokens/s,"
          f" median prompt {statistics.median(t['prompt_per_second'] for t in rows):.0f} tokens/s")


def prompt(a):
    paths = sorted({p for g in a.globs for p in glob.glob(g, recursive=True) if os.path.isfile(p)})
    if not paths:
        print(f"no files match {' '.join(a.globs)}", file=sys.stderr)
        sys.exit(2)
    src = "".join(f"// FILE {p}\n" + open(p, errors="replace").read() + "\n" for p in paths)
    per = max(1, ntokens(src))
    body = src * (a.tokens // per + 1)
    body = body[: int(a.tokens * len(src) / per)]
    text = body + f"\n\nQuestion: {a.question}"
    with open(a.out, "w") as f:
        f.write(text)
    print(f"wrote {a.out}: {ntokens(text)} tokens, from {len(paths)} files")


def rss_gb(pid):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("VmRSS"):
                return int(line.split()[1]) / 1048576
    return 0.0


def growth(a):
    if not os.path.exists(f"/proc/{a.pid}/status"):
        print(f"no process {a.pid}; pass the pid of llama-server ($QWEN_HOME/run/server.pid)", file=sys.stderr)
        sys.exit(2)
    src = open(a.source_file).read()
    msgs = []
    for i in range(a.turns):
        chunk = src[(i * a.chunk) % max(1, len(src)):][: a.chunk]
        msgs.append({"role": "user", "content": f"Turn {i}. Here is more code:\n{chunk}\nReply with one word."})
        r = post("/v1/chat/completions", {"model": "q", "max_tokens": 30, "messages": msgs}, timeout=600)
        msgs.append({"role": "assistant", "content": r["choices"][0]["message"].get("content") or "ok"})
        print(f"turn {i:2d} ctx {r['usage']['prompt_tokens']:6d} rss {rss_gb(a.pid):.2f} GB", flush=True)


def main():
    p = argparse.ArgumentParser(prog="qwen-measure.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("speed")
    s.add_argument("--runs", type=int, default=3)
    s.add_argument("--max-tokens", type=int, default=512)
    s.add_argument("prompt_file")
    s.set_defaults(fn=speed)
    s = sub.add_parser("prompt")
    s.add_argument("--tokens", type=int, required=True)
    s.add_argument("--question", default="Which package in the code above does the most work? Answer in two sentences.")
    s.add_argument("--out", required=True)
    s.add_argument("globs", nargs="+")
    s.set_defaults(fn=prompt)
    s = sub.add_parser("growth")
    s.add_argument("--turns", type=int, default=20)
    s.add_argument("--chunk", type=int, default=11000)
    s.add_argument("--pid", required=True)
    s.add_argument("source_file")
    s.set_defaults(fn=growth)
    a = p.parse_args()
    try:
        a.fn(a)
    except SystemExit as e:
        if isinstance(e.code, str):
            print(e.code, file=sys.stderr)
            sys.exit(2)
        raise


if __name__ == "__main__":
    main()

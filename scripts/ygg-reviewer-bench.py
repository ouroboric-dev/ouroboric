#!/usr/bin/env python3
# The scorer of ygg-reviewer-bench.sh (B-108). Run it as `python3 -I`:
#   ygg-reviewer-bench.py OUT N FAULT LEAF MODEL
# It reads OUT/session-1.jsonl to OUT/session-N.jsonl (the OpenCode events) and OUT/session-N.exit, and prints for
# each session whether the answer is a valid report, then the table. FAULT is a Python regex, or empty for none.
# It reads the events as gleipnir's opencode adapter does (the answer is the text of the last step that said
# anything; tokens and cost are the sums of the step_finish events) and the answer as the engine does
# (gungnir/schema/event.go ParseReport and lastDocument, the report and finding schemas, and the rules of
# jormungandr Review for a first review).
import json, re, sys
out, n, fault, leaf, model = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
pat = re.compile(fault, re.I) if fault else None
FENCE, LOC = "`" * 3, re.compile(r"[^\s:]+:[0-9]+(-[0-9]+)?")
LIMITS = {"id": 100, "source": 100, "location": 300, "claim": 4000, "proof": 2000}
class Bad(Exception):
    pass
def has_document(text):
    dec = json.JSONDecoder()
    for i, c in enumerate(text):
        if c == "{":
            try:
                dec.raw_decode(text, i)
                return True
            except ValueError:
                pass
    return False
def last_document(s):
    s, k = s.strip(), s.count(FENCE)
    if k == 0:
        starts = [i for i, c in enumerate(s) if c == "{"]
        for i in starts:
            try:
                json.loads(s[i:])
                break
            except ValueError:
                pass
        else:
            raise Bad("the answer does not end with a JSON document")
        prose, data = s[:i], s[i:]
    elif k == 1:
        raise Bad("a code fence is not closed")
    elif k > 2:
        raise Bad("more than one code fence")
    elif not s.endswith(FENCE):
        raise Bad("text after the report")
    else:
        o = s.index(FENCE)
        prose, nl, body = s[:o], *s[o:].partition("\n")[1:]
        if not nl:
            raise Bad("a code fence is not closed")
        body = body.strip()
        data = (body[:-3] if body.endswith(FENCE) else body).strip()
    if has_document(prose):
        raise Bad("more than one document")
    return data
def findings(answer):
    try:
        doc = json.loads(last_document(answer))
    except ValueError as e:
        raise Bad(f"not JSON: {e}")
    if not isinstance(doc, dict) or set(doc) != {"findings"} or not isinstance(doc["findings"], list):
        raise Bad('the report is not {"findings": [...]} alone')
    fs, seen = doc["findings"], set()
    if len(fs) > 200:
        raise Bad("more than 200 findings")
    for f in fs:
        if not isinstance(f, dict):
            raise Bad("a finding is not an object")
        if set(f) - set(LIMITS) - {"severity", "status"}:
            raise Bad(f"a finding has an unknown field: {sorted(set(f) - set(LIMITS) - {'severity', 'status'})}")
        for k in ("id", "source", "severity", "location", "claim", "status") + (("proof",) if "proof" in f else ()):
            if not isinstance(f.get(k), str) or (k != "location" and not f[k]):
                raise Bad(f'a finding has no text "{k}"')
            if len(f[k]) > LIMITS.get(k, 100):
                raise Bad(f'a finding\'s "{k}" is too long')
        fid = f["id"]
        if f["severity"] not in ("blocker", "major", "minor"):
            raise Bad(f"finding {fid}: severity {f['severity']!r} is not blocker, major or minor")
        if not LOC.fullmatch(f["location"]):
            raise Bad(f"finding {fid}: location {f['location']!r} is not file:line")
        if f["status"] not in ("open", "disputed"):
            raise Bad(f"finding {fid}: status {f['status']!r} in a first review")
        if f["source"] != "review":
            raise Bad(f"finding {fid} says its source is {f['source']!r}, not review")
        if fid.startswith("check-"):
            raise Bad(f"finding {fid} uses the id space of the checks")
        if fid in seen:
            raise Bad(f"finding id {fid} is used twice")
        seen.add(fid)
    return fs
def session(i):
    text = answer = failed = ""
    steps, broken, cost, use = 0, False, 0.0, {"in": 0, "cw": 0, "read": 0, "out": 0}
    with open(f"{out}/session-{i}.jsonl", encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
    for line in lines:
        line = line.strip()
        try:
            e = json.loads(line) if line.startswith("{") else None
        except ValueError:
            e = None
        if not isinstance(e, dict):
            continue
        t, p = e.get("type"), e.get("part") or {}
        if t == "step_start":
            text = ""
        elif t == "text":
            text += p.get("text") or ""
        elif t == "error":
            err = e.get("error") or {}
            failed = f"{err.get('name', 'error')}: {(err.get('data') or {}).get('message', '')}"
        elif t == "step_finish":
            tk, c = p.get("tokens") or {}, p.get("cost")
            nums = [tk.get("input"), tk.get("output"), (tk.get("cache") or {}).get("read"), (tk.get("cache") or {}).get("write"), c]
            if not all(isinstance(x, (int, float)) for x in nums):
                broken = True
                continue
            steps += 1
            use["in"] += tk["input"]
            use["cw"] += tk["cache"]["write"]
            use["read"] += tk["cache"]["read"]
            use["out"] += tk["output"] + (tk.get("reasoning") or 0)
            cost += c
            if text.strip():
                answer = text
    with open(f"{out}/session-{i}.exit") as fh:
        rc = int(fh.read().strip() or 0)
    known = not broken and not (cost == 0 and sum(use.values()) > 0)
    try:
        if rc == 124:
            raise Bad("the session timed out after 5 minutes")
        if failed:
            raise Bad(failed)
        if rc != 0:
            raise Bad(f"opencode exited {rc}")
        if broken:
            raise Bad("a step_finish event lacks tokens or cost")
        fs, why = findings(answer), ""
    except Bad as e:
        fs, why = None, str(e)
    return fs, why, use, cost if known else None
k = lambda v: f"{v / 1000:.1f}k"
usd = lambda c: "unknown" if c is None else f"${c:.3f}"
rows = [session(i) for i in range(1, n + 1)]
found = 0
for i, (fs, why, use, cost) in enumerate(rows, 1):
    usage = f"{k(use['in'] + use['cw'] + use['read'])} in ({k(use['in'] + use['cw'])} new), {k(use['out'])} out, {usd(cost)}"
    if fs is None:
        print(f"session {i}: not a valid report: {why}; {usage}")
        continue
    hits = [f for f in fs if pat and pat.search(f["claim"] + " " + f["location"])]
    found += bool(hits)
    print(f"session {i}: valid, {len(fs)} finding(s){', fault found' if hits else ''}; {usage}")
    for f in fs:
        claim = " ".join(f["claim"].split())
        print(f"  - {f['severity']} {f['location']}{' [fault]' if f in hits else ''}: {claim[:300]}")
avg = lambda key: sum(r[2][key] for r in rows) / n
costs = [r[3] for r in rows]
print()
print("| Leaf | Model | Sessions | Valid reports | Findings per session | Fault found | Tokens in (new) | Tokens out | Cost per session |")
print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
print(f"| {leaf} | {model} | {n} | {sum(r[0] is not None for r in rows)} | "
      f"{', '.join('-' if r[0] is None else str(len(r[0])) for r in rows)} | {found if pat else '-'} | "
      f"{k(avg('in') + avg('cw') + avg('read'))} ({k(avg('in') + avg('cw'))}) | {k(avg('out'))} | "
      f"{usd(None if None in costs else sum(costs) / n)} |")

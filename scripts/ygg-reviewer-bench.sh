#!/usr/bin/env bash
# Compare reviewer models on a leaf with a known planted fault (B-108; docs/6-journal/2026-10-20-choosing-the-
# reviewer-model.md). IT COSTS MONEY unless --dry-run: each session is one OpenCode session on OpenRouter (a paid
# API: OPENROUTER_API_KEY), about 1 cent for qwen/qwen3.8-27b.
#   ygg-reviewer-bench.sh --model MODEL --leaf DIR --sessions N [--fault REGEX] [--effort low|medium|high|off]
#                         [--out OUT] [--odin DIR] [--tasks DIR] [--dry-run]
# Each session reviews a fresh copy of the leaf (one git commit, no .git of the original) with the prompt the
# engine gives the smoke's reviewer:
#   1. odin's smoke pack reviewer prompt, testdata/smoke-grade/prompts/review.md (odin PRs #21 and #22);
#   2. "## Brief" and the brief of the task, mimir smoke-notes/instruction.md;
#   3. the engine's answer request: jormungandr prompt.go, ReviewRequest and ReportFormat (as of jormungandr
#      ec8f18c), for the reviewer id "review" and the passed check "unit".
# The settings are those of the OpenCode adapter (gleipnir opencode/opencode.go): strict privacy on OpenRouter (no
# data kept, zero retention, no fallback), the effort named on every request (high), read-only permissions, 10
# turns (the graph's max_turns) and 5 minutes. As in qwen-opencode.sh, opencode runs --standalone, with no
# Anthropic credential, no project or Claude Code config, and no update, share or model fetch. Each session has
# its own XDG_DATA_HOME, in a folder under TMPDIR, outside HOME.
# It prints for each session whether the answer is a valid report, by the engine's rules (gungnir ParseReport:
# prose before the report is ignored, nothing may follow it; and jormungandr Review on a first review), and the
# claims of its findings; then the journal's table. A finding is the fault when REGEX (Python, case ignored)
# matches its claim or location: read the claims as well. "Tokens in" counts cache reads, "(new)" does not;
# "Tokens out" includes reasoning. The cost is OpenCode's own figure. A session with tokens and cost 0 (OpenRouter
# reports no cost for the Claude models) makes the cost "unknown".
# OUT (new or empty; default a new folder under TMPDIR) keeps prompt.md, session-N.jsonl (the events),
# session-N.err and summary.md.
# The leaves in scripts/testdata/reviewer-bench, and their --fault:
#   P0  no known fault: the product the failed smoke run built      (no --fault)
#   P1  start.sh runs servr.js                                       'servr'
#   P2  the server listens on 8080, not 3000                         '8080'
#   P3  GET /api/notes returns the oldest first                      'oldest|newest|revers|insertion order'
#   P4  DELETE /api/notes/ID deletes another person's note. server.js reaches notes through notes.of(email);
#       remove in notes.js ignores the owner. Neither file alone shows it.
#       'owner|another (user|person|account)|other (users?|person|people|accounts?)|any (user|person)|not theirs|not the caller|idor'
# YGG_REVIEWER_BENCH_OPENCODE overrides the opencode command (the test's fake). Exit 0, or 2 for a refusal.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() {
  echo "usage: ygg-reviewer-bench.sh --model MODEL --leaf DIR --sessions N [--fault REGEX] [--effort low|medium|high|off] [--out OUT] [--odin DIR] [--tasks DIR] [--dry-run]" >&2
  exit 2
}
fail() { echo "reviewer-bench: $*" >&2; exit 2; }
model="" leaf="" sessions="" fault="" effort=high out="" dry=0
odin="$HERE/../../yggdrasil/odin" tasks="$HERE/../../mimir"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --model) [ $# -ge 2 ] || usage; model="$2"; shift 2 ;;
    --leaf) [ $# -ge 2 ] || usage; leaf="$2"; shift 2 ;;
    --sessions) [ $# -ge 2 ] || usage; sessions="$2"; shift 2 ;;
    --fault) [ $# -ge 2 ] || usage; fault="$2"; shift 2 ;;
    --effort) [ $# -ge 2 ] || usage; effort="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; out="$2"; shift 2 ;;
    --odin) [ $# -ge 2 ] || usage; odin="$2"; shift 2 ;;
    --tasks) [ $# -ge 2 ] || usage; tasks="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$model" ] && [ -n "$leaf" ] && [ -n "$sessions" ] || usage
[[ $sessions =~ ^[1-9][0-9]*$ ]] || fail "--sessions is a whole number above 0, not '$sessions'"
id="${model#openrouter/}"
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || fail "--model '$model' is not an OpenRouter model id, such as qwen/qwen3.8-27b"
case "$effort" in low | medium | high | off) ;; *) fail "--effort is low, medium, high or off, not '$effort'" ;; esac
for tool in python3 git tar timeout; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"; done
[ -d "$leaf" ] || fail "no leaf folder at $leaf (--leaf)"
leaf="$(cd "$leaf" && pwd)"
if [ -n "$fault" ] && ! python3 -I -c 'import re, sys; re.compile(sys.argv[1])' "$fault" 2>/dev/null; then
  fail "--fault '$fault' is not a Python regular expression"
fi
review="$odin/testdata/smoke-grade/prompts/review.md"
brief="$tasks/smoke-notes/instruction.md"
[ -f "$review" ] || fail "$review is missing (--odin): it is the smoke reviewer's prompt"
[ -f "$brief" ] || fail "$brief is missing (--tasks): it is the brief of the task"
[ "$dry" = 1 ] || [ -n "${OPENROUTER_API_KEY:-}" ] || fail "OPENROUTER_API_KEY is not set; use a dedicated OpenRouter key with a credit limit"
if [ -z "$out" ]; then
  out="$(mktemp -d "${TMPDIR:-/tmp}/ygg-reviewer-bench.XXXXXX")"
elif [ -d "$out" ] && [ -n "$(ls -A "$out")" ]; then
  fail "--out $out is not empty; give a new folder"
fi
mkdir -p "$out"
out="$(cd "$out" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ygg-reviewer-bench-work.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

# The prompt, as the engine builds it (odin internal/engine/loop.go, Review): the reviewer's prompt file, the
# brief, then jormungandr.ReviewRequest("review", no open findings, passed ["unit"]).
{
  cat "$review"
  printf '\n\n## Brief\n\n'
  cat "$brief"
  printf '\n\n'
  cat <<'EOF'
## Your answer

Your id is review. Use it as the "source" of every finding.

Answer with one JSON document: end your answer with the document; nothing after it. Any text before it is ignored. The document, bare or in one code fence:

{"findings": [ {"id": "...", "source": "<your id>", "severity": "blocker|major|minor", "location": "path/to/file:LINE", "claim": "what is wrong", "status": "open"} ]}

- "id" names the problem and stays the same every time you report it.
- "location" is a file and a line, or a range such as path/to/file:10-20.
- "status" is "open" for a problem you still see. Say "fixed" only for a problem listed below that you checked
  is gone, and then add "proof": the file:line you read, and the name of one of the checks listed below
  that passed. A finding without both is refused.
- A blocker or major finding of yours that the implementer disputed and a check settled is closed ("overruled"):
  it is not in the list below. Report it again only with proof: a failing check, or a different location than
  before. A repeat with neither is ignored.
- If you find nothing, answer {"findings": []}.

The checks that passed on this work: unit.

The implementer may dispute one of your findings. A dispute is settled by a check: if it holds, the finding is overruled and closed. If you see the same problem again, report it with proof: a failing check, or a different location than the overruled finding. A repeat with neither is ignored.

EOF
} >"$out/prompt.md"

# The session's config, as gleipnir's ConfigJSON makes it for a read-only reviewer under privacy: strict.
reasoning=""
[ "$effort" = off ] || reasoning="\"reasoning\":{\"effort\":\"$effort\"},"
# shellcheck disable=SC2016 # "$schema" is a JSON key, not a variable
conf="$(printf '{"$schema":"https://opencode.ai/config.json","autoupdate":false,"share":"disabled","provider":{"openrouter":{"options":{"apiKey":"{env:OPENROUTER_API_KEY}"},"models":{"%s":{"options":{%s"provider":{"data_collection":"deny","zdr":true,"allow_fallbacks":false}}}}}},"small_model":"openrouter/%s","agent":{"build":{"steps":10}},"permission":{"edit":"deny","bash":"deny","webfetch":"deny","external_directory":"deny","task":"deny","question":"deny"}}' \
  "$id" "$reasoning" "$id")"
env_args=(-u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN "OPENCODE_CONFIG_CONTENT=$conf"
  OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_CLAUDE_CODE=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1
  OPENCODE_DISABLE_AUTOUPDATE=true OPENCODE_DISABLE_SHARE=true OPENCODE_DISABLE_MODELS_FETCH=true)
bin="${YGG_REVIEWER_BENCH_OPENCODE:-opencode}"
cmd=(run --standalone --format json -m "openrouter/$id")

if [ "$dry" = 1 ]; then
  q() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
  echo "Dry run: it spends nothing. Each of the $sessions sessions would copy $leaf (without .git) to"
  echo "$work/leaf-N, commit it there, and run in that folder:"
  printf '  env'
  for a in "${env_args[@]}"; do
    case "$a" in *=*) printf ' %s=%s' "${a%%=*}" "$(q "${a#*=}")" ;; *) printf ' %s' "$a" ;; esac
  done
  printf ' XDG_DATA_HOME=%s timeout 300 %s %s < %s\n' "$(q "$work/data-N")" "$(q "$bin")" "${cmd[*]}" "$(q "$out/prompt.md")"
  echo "The prompt is in $out/prompt.md."
  exit 0
fi

for i in $(seq 1 "$sessions"); do
  copy="$work/leaf-$i"
  mkdir -p "$copy" "$work/data-$i"
  tar -C "$leaf" --exclude=.git -cf - . | tar -C "$copy" -xf -
  git -C "$copy" init -q
  git -C "$copy" add -A
  git -C "$copy" -c user.name=reviewer-bench -c user.email=reviewer-bench@localhost -c commit.gpgsign=false \
    commit -q --no-verify -m "The leaf under review"
  echo "session $i of $sessions" >&2
  rc=0
  (cd "$copy" && env "${env_args[@]}" XDG_DATA_HOME="$work/data-$i" timeout 300 "$bin" "${cmd[@]}") \
    <"$out/prompt.md" >"$out/session-$i.jsonl" 2>"$out/session-$i.err" || rc=$?
  echo "$rc" >"$out/session-$i.exit"
done

# The scorer reads each session's events as gleipnir's opencode adapter does (the answer is the text of the last
# step that said anything; tokens and cost are the sums of the step_finish events) and the answer as the engine
# does (gungnir/schema/event.go ParseReport and lastDocument, the report and finding schemas, and the rules of
# jormungandr Review for a first review).
score="$(cat <<'PY'
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
    for line in open(f"{out}/session-{i}.jsonl", encoding="utf-8", errors="replace"):
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
    rc = int(open(f"{out}/session-{i}.exit").read().strip() or 0)
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
PY
)"
python3 -I -c "$score" "$out" "$sessions" "$fault" "$(basename "$leaf")" "$id" | tee "$out/summary.md"
echo "The prompt, the events of each session and this summary are in $out."

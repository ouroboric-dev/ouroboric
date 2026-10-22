#!/usr/bin/env bash
# Check the journey journal against spec §10.5 and design success criterion 6.
#   journal-check.sh [JOURNAL_DIR]      default: docs/6-journal beside this script's repo
# Every entry (a file named YYYY-MM-DD-*.md) must have:
#   - front matter with date (the file name's), tags, status (open, resolved or abandoned), post-candidate (yes or
#     no) and evidence (a list, flow or block style; not empty once the entry is resolved);
#   - the sections Challenge, Context, Options, Decision, Result and Lessons, in that order (headings inside fenced
#     code blocks do not count);
#   - a Result that is not "pending" once the entry is resolved;
#   - one row in README.md with the same date, status and post candidate, and no row for a file that is not there;
#   - no raw ledger line (a private run's ledger is quoted by aggregate numbers only).
# An entry tagged factory-change that is resolved or abandoned must cite its before and after in its Result: the
# words `ygg metrics --compare` and two different run ids (criterion 6: a factory change cites `--compare`).
# It reads and prints; it changes nothing. Exit 0 when the journal passes, 1 when a rule fails, 2 on bad usage.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="${1:-$HERE/../docs/6-journal}"
[ $# -le 1 ] || { echo "usage: journal-check.sh [JOURNAL_DIR]" >&2; exit 2; }
[ -d "$dir" ] || { echo "journal-check: no journal at $dir" >&2; exit 2; }
exec python3 -I - "$dir" <<'PY'
import os, re, sys

jdir = sys.argv[1]
SECTIONS = ["Challenge", "Context", "Options", "Decision", "Result", "Lessons"]
STATUS = {"open", "resolved", "abandoned"}
RUN = re.compile(r"\b\d{8}-\d{6}-[0-9a-f]{6}\b")
FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
LEDGER = re.compile(r'^\s*(?:[-*]\s+)?\{\s*"schema"\s*:\s*"ygg\.ledger/', re.M)
ROW = re.compile(r"^\| (\d{4}-\d\d-\d\d) \| \[[^\]]*\]\(([^)]+)\) \| [^|]*\| (\w+) \| (\w+) \|", re.M)
problems = []


def bad(file, msg):
    problems.append(f"{file}: {msg}")


def clean(s):
    return s.strip().strip("\"'").strip()


def parse_front(text):
    # Scalars go in fm; list items (block style: "  - item" under a key) go in lists.
    fm, lists, cur = {}, {}, None
    for line in text.split("\n"):
        m = re.match(r"^([\w-]+):(.*)$", line)
        if m:
            cur = m.group(1)
            fm[cur] = m.group(2).strip()
            lists.setdefault(cur, [])
            continue
        m = re.match(r"^\s*-\s+(.*)$", line)
        if m and cur is not None:
            lists[cur].append(m.group(1))
    return fm, lists


def items(fm, lists, key):
    # A list in flow style ([a, "b"]) or block style; quotes and spaces are stripped from each item.
    v = fm.get(key, "")
    if v.startswith("["):
        raw = v[1:].rsplit("]", 1)[0].split(",")
    else:
        raw = lists.get(key, [])
    return [c for c in (clean(x) for x in raw) if c]


def visible(body):
    # The body with the headings inside fenced code blocks blanked, so they neither count as sections nor end Result.
    out, fence = [], None
    for line in body.split("\n"):
        m = FENCE.match(line)
        if fence is None:
            if m:
                fence = m.group(1)
            out.append(line)
        elif m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and line.strip() == m.group(1):
            fence = None
            out.append(line)
        else:
            out.append("" if re.match(r"^\s*#{1,6}\s", line) else line)
    return "\n".join(out)


entries = sorted(f for f in os.listdir(jdir) if re.match(r"\d{4}-\d\d-\d\d-.*\.md$", f))
facts = {}
for f in entries:
    text = open(os.path.join(jdir, f), encoding="utf-8").read()
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        bad(f, "front matter is missing")
        continue
    fm, lists = parse_front(m.group(1))
    for key in ("date", "tags", "status", "post-candidate", "evidence"):
        if key not in fm:
            bad(f, f"front matter lacks {key}")
    date, status, post = clean(fm.get("date", "")), clean(fm.get("status", "")), clean(fm.get("post-candidate", ""))
    if "status" in fm and status not in STATUS:
        bad(f, f"status '{status}' is not open, resolved or abandoned")
    if "post-candidate" in fm and post not in ("yes", "no"):
        bad(f, f"post-candidate '{post}' is not yes or no")
    if "date" in fm and date != f[:10]:
        bad(f, f"date {date} is not the file name's")
    body = text[m.end():]
    seen = visible(body)
    heads = re.findall(r"^## (\w+)\s*$", seen, re.M)
    for s in SECTIONS:
        if s not in heads:
            bad(f, f"section {s} is missing")
    present = [h for h in heads if h in SECTIONS]
    if all(s in heads for s in SECTIONS) and present != SECTIONS:
        bad(f, "the sections are not in the order " + ", ".join(SECTIONS))
    result = ""
    rm = re.search(r"^## Result\s*$(.*?)(?=^## |\Z)", seen, re.S | re.M)
    if rm:
        result = rm.group(1).strip()
    evidence = items(fm, lists, "evidence")
    if status == "resolved" and not evidence:
        bad(f, "resolved but evidence is empty")
    if status == "resolved" and result.lower().rstrip(".") == "pending":
        bad(f, "resolved but its Result is pending")
    tags = items(fm, lists, "tags")
    if "factory-change" in tags and status in ("resolved", "abandoned"):
        if "ygg metrics --compare" not in result:
            bad(f, "tagged factory-change but its Result does not cite ygg metrics --compare")
        elif len(set(RUN.findall(result))) < 2:
            bad(f, "its ygg metrics --compare citation does not name two different run ids")
    if LEDGER.search(body):
        bad(f, "holds a raw ledger line; quote aggregate numbers and link the run by id")
    facts[f] = (date, status, post)

index = os.path.join(jdir, "README.md")
if os.path.isfile(index):
    rows = {}
    for d, link, status, post in ROW.findall(open(index, encoding="utf-8").read()):
        rows.setdefault(link, []).append((d, status, post))
    for f in entries:
        if f not in rows:
            bad(f, "not in README.md")
            continue
        if len(rows[f]) > 1:
            bad(f, f"has {len(rows[f])} rows in README.md")
        if f in facts:
            d, status, post = rows[f][0]
            fd, fs, fp = facts[f]
            if d != fd:
                bad(f, f"README.md row says date {d}, the entry says {fd}")
            if (status, post) != (fs, fp):
                bad(f, f"README.md says {status}/{post}, the entry says {fs}/{fp}")
    for link in rows:
        if link not in entries:
            bad("README.md", f"lists {link}, which is not there")
else:
    bad("README.md", "is missing")

for p in problems:
    print(p)
print(f"journal-check: {len(entries)} entries, {len(problems)} problem(s)")
sys.exit(1 if problems else 0)
PY

#!/usr/bin/env bash
# Say whether one ygg run used the repair path of a loop, read from its ledger (B-109).
#   ygg-repair-path.sh LEDGER
# The repair path is three steps, in this order in the ledger:
#   1. raised: a finding_raised line, on the loop's node N, for finding F;
#   2. fixed: an implementer session of the loop finished after it: a node_finished line on node N (odin logs the
#      reviewers' sessions on N-<reviewer id>, so they do not count);
#   3. closed: a finding_closed line for F after that, which its source logs when it confirms the fix.
# The event names are gungnir's (event.go); the order is odin's loop (internal/engine/loop.go). A finding that a
# check overruled is not closed by its source, so it does not complete the path.
# It prints one line, "repair path: finding raised, fixed, closed (...)" or "repair path: missing step STEP: ..."
# for the finding that came furthest, and the counts. Exit 0 when one finding took the whole path, 1 when none
# did, 2 for a refusal. The ledger holds no credential; this script reads nothing else.
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: ygg-repair-path.sh LEDGER" >&2; exit 2; }
[ -f "$1" ] || { echo "ygg-repair-path: no ledger at $1" >&2; exit 2; }
python3 -I - "$1" <<'PY'
import json, sys

events = []
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if isinstance(e, dict):
            events.append(e)

# For each finding, in the order it was first raised: the step it reached.
findings = {}
for e in events:
    name, node, fid = e.get("event"), e.get("ygg.node.id", ""), e.get("ygg.finding.id", "")
    if name == "finding_raised":
        if fid and fid not in findings:
            findings[fid] = {"node": node, "source": e.get("ygg.finding.source", "?"), "note": e.get("ygg.note", ""),
                             "raised": e.get("ygg.attempt", "?"), "fixed": False, "closed": None, "overruled": False}
    elif name == "node_finished":
        for r in findings.values():
            if r["node"] == node:
                r["fixed"] = True
    elif name in ("finding_closed", "finding_overruled"):
        r = findings.get(fid)
        if r is None or not r["fixed"]:
            continue  # a close before any fix is not the repair path
        if name == "finding_closed" and r["closed"] is None:
            r["closed"] = e.get("ygg.attempt", "?")
        elif name == "finding_overruled":
            r["overruled"] = True

closed = sum(1 for r in findings.values() if r["closed"] is not None)
counts = "%d finding(s) raised, %d closed" % (len(findings), closed)
if not findings:
    print("repair path: missing step raised: no finding was raised (%s)" % counts)
    sys.exit(1)
done = [(fid, r) for fid, r in findings.items() if r["closed"] is not None]
if done:
    fid, r = done[0]
    print("repair path: finding raised, fixed, closed (finding %s from %s, raised in attempt %s, closed in attempt %s: %s; %s)"
          % (fid, r["source"], r["raised"], r["closed"], r["note"], counts))
    sys.exit(0)
fixed = [(fid, r) for fid, r in findings.items() if r["fixed"]]
if fixed:
    fid, r = fixed[0]
    why = "; it was overruled by a check, not closed by its source" if r["overruled"] else ""
    print("repair path: missing step closed: finding %s was raised and an implementer session finished after it, but it was not closed%s (%s)"
          % (fid, why, counts))
    sys.exit(1)
fid, r = next(iter(findings.items()))
print("repair path: missing step fixed: finding %s was raised in attempt %s, but no implementer session of node %s finished after it (%s)"
      % (fid, r["raised"], r["node"], counts))
sys.exit(1)
PY

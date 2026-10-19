#!/usr/bin/env bash
# Print what one ygg run spent, read from its ledger.
#   ygg-cost.sh LEDGER [FACTORY_YAML]
# Every ledger line that carries a session's usage is added up: the lines of the finished and the failed sessions.
# The run's own totals (run_finished, run_paused, run_failed) are left out, because they repeat the sessions. The
# cost is the sum of ygg.usage.cost_usd; a cost the adapter estimated is marked as such. With FACTORY_YAML, the
# per_run cap is printed beside the spend. The ledger holds no credential; this script reads nothing else.
set -euo pipefail
[ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: ygg-cost.sh LEDGER [FACTORY_YAML]" >&2; exit 2; }
[ -f "$1" ] || { echo "ygg-cost: no ledger at $1" >&2; exit 2; }
python3 -I - "$1" <<'PY'
import json, sys
totals = {"run_finished", "run_paused", "run_failed"}
n = tin = tout = cache = turns = 0
usd = 0.0
estimated = False
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if not isinstance(e, dict) or e.get("event") in totals:
            continue
        keys = ("gen_ai.usage.input_tokens", "gen_ai.usage.output_tokens", "ygg.usage.turns", "ygg.usage.cost_usd")
        if not any(e.get(k) for k in keys):
            continue
        n += 1
        tin += e.get("gen_ai.usage.input_tokens") or 0
        tout += e.get("gen_ai.usage.output_tokens") or 0
        cache += e.get("gen_ai.usage.cache_read.input_tokens") or 0
        turns += e.get("ygg.usage.turns") or 0
        usd += e.get("ygg.usage.cost_usd") or 0.0
        estimated = estimated or bool(e.get("ygg.usage.cost_estimated"))
print("ygg-cost: %d session line(s): %d tokens in, %d out, %d cache read, %d turns" % (n, tin, tout, cache, turns))
print("ygg-cost: cost $%.4f%s" % (usd, " (at least one session's cost is an estimate)" if estimated else ""))
PY
if [ $# -eq 2 ] && [ -f "$2" ]; then
  cap="$( (grep -E '^  per_run:' "$2" || true) | head -n 1 | sed -n 's/.*usd:[[:space:]]*\([0-9.]*\).*/\1/p')"
  if [ -n "$cap" ]; then echo "ygg-cost: the per_run cap is \$$cap"; else echo "ygg-cost: the per_run cap unknown (no per_run usd in $2)"; fi
fi

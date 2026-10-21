#!/usr/bin/env bash
# Tests for ygg-repair-path.sh: does a run's ledger show one finding raised, fixed and closed (B-109).
#   scripts/tests/ygg-repair-path.test.sh
# The ledgers are made up here, with the field names of gungnir event.go and the order of odin's loop
# (internal/engine/loop.go): the implementer's node_finished on the loop node, the reviewer's on node-reviewer.
# shellcheck disable=SC2329 # check calls has and hasnt by name
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/.."
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
run() { "$S/ygg-repair-path.sh" "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }

# One ledger line: event, node, attempt, and optionally a finding id and its source.
ev() {
  local name="$1" node="$2" attempt="$3" id="${4:-}" src="${5:-review}"
  if [ -n "$id" ]; then
    printf '{"schema":"1","seq":0,"ygg.run.id":"r","event":"%s","ygg.node.id":"%s","ygg.attempt":%s,"ygg.finding.id":"%s","ygg.finding.source":"%s","ygg.note":"server.js:3: the port is 8080","prev":""}\n' \
      "$name" "$node" "$attempt" "$id" "$src"
  else
    printf '{"schema":"1","seq":0,"ygg.run.id":"r","event":"%s","ygg.node.id":"%s","ygg.attempt":%s,"gen_ai.agent.name":"implementer","prev":""}\n' \
      "$name" "$node" "$attempt"
  fi
}

# --- the whole repair path: raised in attempt 1, the implementer runs in attempt 2, closed in attempt 2
{
  ev run_started "" 0
  ev node_finished build 1
  ev node_finished build-review 1
  ev finding_raised build 1 F1
  ev loop_attempt build 2
  ev node_finished build 2
  ev node_finished build-review 2
  ev finding_closed build 2 F1
  echo 'not json'
} >"$T/full.jsonl"
run "$T/full.jsonl"
check "the whole path exits 0" test "$rc" -eq 0
check "it says raised, fixed, closed" has "repair path: finding raised, fixed, closed"
check "it names the finding and its source" has "finding F1 from review"
check "it names the attempts" has "raised in attempt 1, closed in attempt 2"
check "it quotes the finding" has "server.js:3: the port is 8080"

# --- no finding at all
{ ev node_finished build 1; ev node_finished build-review 1; } >"$T/none.jsonl"
run "$T/none.jsonl"
check "no finding exits 1" test "$rc" -eq 1
check "no finding names the missing step raised" has "repair path: missing step raised: no finding was raised"

# --- raised, but no implementer session after it (only the reviewer's line, and one before the raise)
{ ev node_finished build 1; ev finding_raised build 1 F1; ev node_finished build-review 1; } >"$T/unfixed.jsonl"
run "$T/unfixed.jsonl"
check "raised but not fixed exits 1" test "$rc" -eq 1
check "it names the missing step fixed" has "repair path: missing step fixed: finding F1 was raised in attempt 1, but no implementer session of node build finished after it"

# --- raised and an implementer session after it, but never closed
{ ev finding_raised build 1 F1; ev node_finished build 2; ev node_finished build-review 2; } >"$T/open.jsonl"
run "$T/open.jsonl"
check "raised and fixed but not closed exits 1" test "$rc" -eq 1
check "it names the missing step closed" has "repair path: missing step closed: finding F1 was raised and an implementer session finished after it, but it was not closed"
check "it does not claim an overrule" hasnt "overruled"

# --- overruled by a check: not closed by its source
{ ev finding_raised build 1 F1; ev node_finished build 2; ev finding_overruled build 2 F1; } >"$T/overruled.jsonl"
run "$T/overruled.jsonl"
check "an overruled finding exits 1" test "$rc" -eq 1
check "it says the finding was overruled, not closed" has "it was overruled by a check, not closed"

# --- two findings: one stays open, the other completes the path; the counts are printed
{
  ev finding_raised build 1 F1; ev finding_raised build 1 F2 check:unit
  ev node_finished build 2; ev finding_closed build 2 F2
} >"$T/two.jsonl"
run "$T/two.jsonl"
check "one complete finding of two exits 0" test "$rc" -eq 0
check "it names the finding that completed the path" has "finding F2 from check:unit"
check "it counts the findings" has "2 finding(s) raised, 1 closed"

# --- a closed line before the fix does not count
{ ev finding_raised build 1 F1; ev finding_closed build 1 F1; ev node_finished build 2; } >"$T/early.jsonl"
run "$T/early.jsonl"
check "a close before the fix is not the repair path" test "$rc" -eq 1
check "and the missing step is closed" has "missing step closed"

# --- usage
run
check "no argument exits 2" test "$rc" -eq 2
run "$T/no-such.jsonl"
check "a missing ledger exits 2" test "$rc" -eq 2
check "and says so" has "no ledger at"

[ "$fail" -eq 0 ] && echo "all ygg-repair-path tests passed"
exit "$fail"

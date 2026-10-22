#!/usr/bin/env bash
# Tests for journal-check.sh: a good journal passes, and each rule of the checker fails on a journal that breaks it.
#   scripts/tests/journal-check.test.sh      Exit 0 when every case behaves.
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
run() { "$@" >"$T/out" 2>&1; rc=$?; }
# shellcheck disable=SC2329  # has runs through check
has() { grep -q -F -- "$1" "$T/out"; }

RUN_A=20261023-090000-a1b2c3
RUN_B=20261024-090000-d4e5f6

# entry FILE STATUS POST TAGS EVIDENCE RESULT: writes one entry with every section.
entry() {
  local file="$1" status="$2" post="$3" tags="$4" evidence="$5" result="$6"
  local date="${file:0:10}"
  cat > "$J/$file" <<EOT
---
date: $date
tags: [$tags]
status: $status
post-candidate: $post
evidence: [$evidence]
---
## Challenge
What went wrong.
## Context
What we knew.
## Options
What we considered.
## Decision
What we chose.
## Result
$result
## Lessons
What we would tell someone.
EOT
}
index() { # index LINE...: writes README.md with the table header and the given rows
  { echo "# Journal"; echo; echo "| Date | Entry | Tags | Status | Post candidate |"; echo "| --- | --- | --- | --- | --- |"; printf '%s\n' "$@"; } > "$J/README.md"
}
fresh() { J="$T/journal-$1"; mkdir -p "$J"; }

fresh good
entry 2026-10-23-first.md resolved yes "harness, cost" '"run 20261023-090000-a1b2c3"' "Measured: it took 3 attempts, then 2."
entry 2026-10-24-open.md open no "loop" "" "pending"
entry 2026-10-25-change.md resolved yes "harness, factory-change" '"run 20261023-090000-a1b2c3", "run 20261024-090000-d4e5f6"' "ygg metrics --compare $RUN_A $RUN_B: first pass 50% to 75%, reward held."
index "| 2026-10-23 | [first](2026-10-23-first.md) | harness, cost | resolved | yes |" \
      "| 2026-10-24 | [open](2026-10-24-open.md) | loop | open | no |" \
      "| 2026-10-25 | [change](2026-10-25-change.md) | harness, factory-change | resolved | yes |"
run "$S/journal-check.sh" "$J"
check "a good journal passes" test "$rc" -eq 0
check "and says how many entries it read" has "3 entries"

# shellcheck disable=SC2329  # runs through check
failed_with() { [ "$rc" = 1 ] && has "$1"; }
bad() { # bad NAME EXPECT: run the checker on the current $J and expect exit 1 and a message with EXPECT
  run "$S/journal-check.sh" "$J"
  check "$1" failed_with "$2"
}

fresh nofm;   entry 2026-10-23-a.md open no "x" "" "pending"; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | open | no |"; sed -i '1d' "$J/2026-10-23-a.md"
bad "an entry with no front matter fails" "2026-10-23-a.md: front matter"
fresh nokey;  entry 2026-10-23-a.md open no "x" "" "pending"; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | open | no |"; sed -i '/^post-candidate:/d' "$J/2026-10-23-a.md"
bad "a missing key fails" "2026-10-23-a.md: front matter lacks post-candidate"
fresh badstat; entry 2026-10-23-a.md "done" no "x" "" "pending"; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | done | no |"
bad "a status that is not open, resolved or abandoned fails" "status 'done'"
fresh baddate; entry 2026-10-23-a.md open no "x" "" "pending"; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | open | no |"; sed -i 's/^date: .*/date: 2026-10-22/' "$J/2026-10-23-a.md"
bad "a date that is not the file name's fails" "date 2026-10-22 is not the file name's"
fresh nosec;  entry 2026-10-23-a.md open no "x" "" "pending"; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | open | no |"; sed -i '/^## Options$/,+1d' "$J/2026-10-23-a.md"
bad "a missing section fails" "section Options"
fresh order;  entry 2026-10-23-a.md open no "x" "" "pending"; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | open | no |"; sed -i 's/^## Context$/## ContextX/;s/^## Options$/## Context/;s/^## ContextX$/## Options/' "$J/2026-10-23-a.md"
bad "sections out of order fail" "sections are not in the order"
fresh noevid; entry 2026-10-23-a.md resolved no "x" "" "Measured: fine."; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | resolved | no |"
bad "a resolved entry with no evidence fails" "resolved but evidence is empty"
fresh pend;   entry 2026-10-23-a.md resolved no "x" '"run 20261023-090000-a1b2c3"' "pending"; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | resolved | no |"
bad "a resolved entry whose result is pending fails" "resolved but its Result is pending"
fresh noidx;  entry 2026-10-23-a.md open no "x" "" "pending"; index
bad "an entry missing from the index fails" "2026-10-23-a.md: not in README.md"
fresh difidx; entry 2026-10-23-a.md open no "x" "" "pending"; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | resolved | yes |"
bad "an index row that disagrees with the entry fails" "README.md says resolved/yes"
fresh ghost;  entry 2026-10-23-a.md open no "x" "" "pending"; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | open | no |" "| 2026-10-24 | [gone](2026-10-24-gone.md) | x | open | no |"
bad "an index row for a file that is not there fails" "README.md: lists 2026-10-24-gone.md"
fresh nocomp; entry 2026-10-23-a.md resolved yes "harness, factory-change" '"run 20261023-090000-a1b2c3"' "It got better."; index "| 2026-10-23 | [a](2026-10-23-a.md) | harness, factory-change | resolved | yes |"
bad "a factory change with no ygg metrics --compare fails" "factory-change but its Result does not cite ygg metrics --compare"
fresh onerun; entry 2026-10-23-a.md resolved yes "factory-change" '"run 20261023-090000-a1b2c3"' "ygg metrics --compare $RUN_A: better."; index "| 2026-10-23 | [a](2026-10-23-a.md) | factory-change | resolved | yes |"
bad "a comparison that names one run fails" "two different run ids"
fresh ledger; entry 2026-10-23-a.md open no "x" "" '{"schema":"ygg.ledger/v1","seq":1,"event":"run_started"}'; index "| 2026-10-23 | [a](2026-10-23-a.md) | x | open | no |"
bad "a raw ledger line in an entry fails" "a raw ledger line"

fresh ok2; entry 2026-10-23-a.md open no "factory-change" "" "pending"; index "| 2026-10-23 | [a](2026-10-23-a.md) | factory-change | open | no |"
run "$S/journal-check.sh" "$J"
check "an open factory-change entry may still be waiting for its comparison" test "$rc" -eq 0
run "$S/journal-check.sh" "$T/no-such-folder"
check "a folder that is not there is a usage error" test "$rc" -eq 2
check "and the message says there is no journal" has "no journal"
run "$S/journal-check.sh" "$S/../docs/6-journal"
check "the real journal passes" test "$rc" -eq 0

exit "$fail"

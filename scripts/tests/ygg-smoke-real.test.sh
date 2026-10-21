#!/usr/bin/env bash
# Tests for ygg-smoke-real.sh: which `ygg` it says it runs (B-111), the run from a planted-fault leaf (B-109)
# and another implementer (B-110).   scripts/tests/ygg-smoke-real.test.sh
# Each case uses a fake `ygg`, a fake `go` and made-up credentials: no model, no engine, no money. Most cases are
# --dry-run. The cases of the run's tail run without it, only through run_real, which refuses unless YGG_CMD is a
# fake in this test's temp folder.
# shellcheck disable=SC2329,SC2016 # check calls has and hasnt by name; the $ in the patterns is literal
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
# The script names its folder by the second, so each run waits for the next second.
run() { sleep 1; "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
export HOME="$T/home"; mkdir -p "$HOME"
export YGG_ENGINE_CHECK=0 # the engine environment has its own test (ygg-engine.test.sh)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export YGG_BIND="$T/bind"; mkdir -p "$YGG_BIND"

# A made-up mimir and a made-up odin (a git repo, so the build case can name its commit).
M="$T/mimir"; mkdir -p "$M/smoke-notes/sample-suite/tests"
printf '[metadata]\nsuite = "v1"\n' >"$M/smoke-notes/task.toml"
printf '# brief\n' >"$M/smoke-notes/instruction.md"
printf '{}\n' >"$M/smoke-notes/sample-suite/tests/manifest.json"
printf '#!/bin/bash\n' >"$M/smoke-notes/sample-suite/tests/test.sh"
O="$T/odin"; mkdir -p "$O/testdata/smoke-grade/templates/notes"
printf 'name: smoke-grade\nleaves:\n  repos/notes: { description: the notes product, template: templates/notes, first_commit: [LICENSE] }\n' \
  >"$O/testdata/smoke-grade/pack.yaml"
printf 'licence\n' >"$O/testdata/smoke-grade/templates/notes/LICENSE"
printf 'old\n' >"$O/testdata/smoke-grade/templates/notes/OLD.md"
printf 'roles:\n  implementer: { agent: claude-code, model: sonnet }\n  reviewer: { agent: opencode, model: openrouter/qwen/qwen3.8-27b }\n' \
  >"$O/testdata/smoke-grade/factory.real.example.yaml"
printf 'sandbox:\n  engine: @ENGINE@\n  mounts:\n    - { host: @FOLDER@, engine: @BIND@ }\ngrader: { tasks_dir: @TASKS@, suite_dir: @SUITES@ }\n' \
  >>"$O/testdata/smoke-grade/factory.real.example.yaml"
git -C "$O" init -q -b main
git -C "$O" add testdata
git -C "$O" -c user.name=t -c user.email=t@example.invalid commit -q -m odin
odin_sha="$(git -C "$O" rev-parse --short HEAD)"
D="$T/it"; mkdir -p "$D"
printf 'engine: unix://%s/engine.sock\n' "$T" >"$D/factory.yaml"
printf 'CLAUDE_CODE_OAUTH_TOKEN=made-up-a\nOPENROUTER_API_KEY=made-up-b\n' >"$T/factory.env"
rargs=(--folder "$D" --tasks "$M" --odin "$O" --env "$T/factory.env" --dry-run)

# A fake ygg that accepts every verb, and a fake go whose build writes that same fake to the -o path.
mkdir -p "$T/pathbin" "$T/other" "$T/gobin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/pathbin/ygg"
cp "$T/pathbin/ygg" "$T/other/ygg-custom"
cat >"$T/gobin/go" <<'EOF2'
#!/usr/bin/env bash
[ "$1" = build ] && [ "$2" = -o ] && { printf '#!/usr/bin/env bash\nexit 0\n' >"$3"; chmod +x "$3"; exit 0; }
exit 1
EOF2
chmod +x "$T/pathbin/ygg" "$T/other/ygg-custom" "$T/gobin/go"
touch -d '2026-01-02 03:04:05' "$T/pathbin/ygg" "$T/other/ygg-custom"
BASEPATH="$PATH"

# --- a ygg from PATH
PATH="$T/pathbin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "a dry run with a ygg on PATH exits 0" test "$rc" -eq 0
check "it says the path of the ygg that runs" has "smoke-real: ygg: $T/pathbin/ygg"
check "it says the mtime of that binary" has "modified 2026-01-02"
check "it says no commit is known for a binary it did not build" has "odin commit unknown"
check "the line comes before the doctor" bash -c "grep -n 'smoke-real: ygg:' '$T/out' | head -n 1 | cut -d: -f1 | { read -r a; b=\$(grep -n 'ygg doctor on that config' '$T/out' | cut -d: -f1); [ \"\$a\" -lt \"\$b\" ]; }"

# --- YGG_CMD
PATH="$T/pathbin:$BASEPATH" YGG_CMD="$T/other/ygg-custom" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "YGG_CMD wins over PATH and the line names it" has "smoke-real: ygg: $T/other/ygg-custom"
check "and does not name the PATH one" hasnt "$T/pathbin/ygg"

# --- no ygg: built from --odin, clean tree
PATH="$T/gobin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "a build from --odin exits 0" test "$rc" -eq 0
check "the line names the built binary" has "/bin/ygg"
check "the line names the odin commit" has "built from $O at commit $odin_sha"
check "a clean tree is said to be clean" has "tree clean"

# --- no ygg: built from --odin, dirty tree
printf 'x\n' >"$O/untracked.txt"
PATH="$T/gobin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "a dirty odin tree is said to be dirty" has "tree DIRTY"

# The run's folder, from the line "smoke-real: made DIR".
work() { sed -n 's/^smoke-real: made //p' "$T/out" | head -n 1; }
export PATH="$T/pathbin:$BASEPATH"

# --- the default run: odin's pack, the empty template, the example's implementer (B-109, B-110)
run "$S/ygg-smoke-real.sh" "${rargs[@]}"
W="$(work)"
check "a default run uses odin's pack as the graph" has "--graph '$O/testdata/smoke-grade'"
check "a default run copies no pack" test ! -e "$W/pack"
check "a default run's start.sh runs the leaf's start.sh as a program" grep -q -F 'exec ./start.sh' "$W/project/start.sh"
check "a default run keeps the example's implementer" grep -q -F 'implementer: { agent: claude-code, model: sonnet }' "$W/factory.yaml"
check "a default run prints the implementer" has "smoke-real: the implementer: { agent: claude-code, model: sonnet }"
check "a default run says nothing about the repair path" hasnt "repair"

# --- --clip: the whole report.txt goes to the clipboard after the run, with clip.exe (B-111, B-109)
mkdir -p "$T/clipbin"; printf '#!/bin/sh\ncat >/dev/null\n' >"$T/clipbin/clip.exe"; chmod +x "$T/clipbin/clip.exe"
PATH="$T/clipbin:$PATH" run "$S/ygg-smoke-real.sh" "${rargs[@]}" --clip
check "a dry run with --clip and clip.exe exits 0" test "$rc" -eq 0
check "it says report.txt goes to the clipboard after the run" has "smoke-real: after the run: report.txt is copied to the clipboard with clip.exe"
NOCLIP="$(tr ':' '\n' <<<"$PATH" | while IFS= read -r d; do [ -e "$d/clip.exe" ] || printf '%s:' "$d"; done)"
PATH="${NOCLIP%:}" run "$S/ygg-smoke-real.sh" "${rargs[@]}" --clip
check "a dry run with --clip and no clip.exe still exits 0" test "$rc" -eq 0
check "it says --clip needs clip.exe" has "smoke-real: --clip needs clip.exe (WSL); the report will be in report.txt only"
check "the evidence script never gets --clip" bash -c "! grep -q -E 'ygg-evidence\.sh.*(--clip|clip\[)' '$S/ygg-smoke-real.sh'"

# --- --from-leaf: the run starts from a planted-fault leaf (B-109)
L="$T/leaf"; mkdir -p "$L/lib" "$L/.git"
printf 'licence\n' >"$L/LICENSE"; printf '# notes\n' >"$L/README.md"; printf 'listen(8080)\n' >"$L/server.js"
printf 'x\n' >"$L/lib/notes.js"; printf 'git\n' >"$L/.git/HEAD"
printf '#!/bin/sh\nexec node server.js\n' >"$L/start.sh"; chmod +x "$L/start.sh"
cp "$O/testdata/smoke-grade/pack.yaml" "$T/pack.before"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --from-leaf "$L"
W="$(work)"
check "a dry run from a leaf exits 0" test "$rc" -eq 0
check "it says which leaf the run starts from" has "smoke-real: the leaf repos/notes starts from $L"
check "the graph is the run's own copy of the pack" has "--graph '$W/pack'"
check "the copy's template holds the leaf's files" cmp -s "$L/server.js" "$W/pack/templates/notes/server.js"
check "and its nested files" cmp -s "$L/lib/notes.js" "$W/pack/templates/notes/lib/notes.js"
check "but not its .git" test ! -e "$W/pack/templates/notes/.git"
check "the old template's files are gone" bash -c "[ \"\$(ls '$W/pack/templates/notes' | tr '\n' ' ')\" = 'LICENSE README.md lib server.js start.sh ' ]"
check "every leaf file is in the first commit" grep -q -F 'first_commit: [LICENSE, README.md, lib/notes.js, server.js, start.sh]' "$W/pack/pack.yaml"
check "the rest of the pack line stays" grep -q -F 'repos/notes: { description: the notes product, template: templates/notes, first_commit:' "$W/pack/pack.yaml"
check "odin's own pack is not changed" cmp -s "$T/pack.before" "$O/testdata/smoke-grade/pack.yaml"
check "start.sh runs the leaf's start.sh as a program when it is executable" grep -q -F 'if [ -x ./start.sh ]; then exec ./start.sh; else exec sh ./start.sh; fi' "$W/project/start.sh"
# The wrapper itself, run against a leaf start.sh with and without the x bit (odin writes first-commit files 0644).
mkdir -p "$T/app/repos/notes"; cp "$W/project/start.sh" "$T/app/start.sh"
printf '#!/bin/sh\necho started\n' >"$T/app/repos/notes/start.sh"; chmod 644 "$T/app/repos/notes/start.sh"
check "the wrapper runs a 0644 start.sh with sh" bash -c "[ \"\$('$T/app/start.sh')\" = started ]"
printf '#!/usr/bin/env bash\n[[ -n x ]] && echo bash-started\n' >"$T/app/repos/notes/start.sh"; chmod 755 "$T/app/repos/notes/start.sh"
check "the wrapper runs an executable start.sh by its own shebang" bash -c "[ \"\$('$T/app/start.sh')\" = bash-started ]"
check "a run from a leaf says it checks the repair path after the run" has "smoke-real: after the run: ygg-repair-path.sh checks the repair path in the run's ledger (--from-leaf)"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --from-leaf "$L" --build
check "the dry run names the sandbox build on the copy" has "--realm '$(work)/pack'"

run "$S/ygg-smoke-real.sh" "${rargs[@]}" --from-leaf "$T/no-such-leaf"
check "a missing leaf folder is refused" test "$rc" -eq 2
check "and named" has "no leaf folder at $T/no-such-leaf"
L2="$T/leaf-odd"; mkdir -p "$L2"; printf 'x\n' >"$L2/a b.js"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --from-leaf "$L2"
check "a leaf file name that needs quoting in YAML is refused" test "$rc" -eq 2
check "and named" has "a b.js"
L3="$T/leaf-empty"; mkdir -p "$L3/.git"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --from-leaf "$L3"
check "a leaf with no files is refused" test "$rc" -eq 2

# --- --implementer: the implementer role of the run's factory.yaml (B-110)
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --implementer opencode:openrouter/qwen/qwen3.8-27b
W="$(work)"
check "a dry run with another implementer exits 0" test "$rc" -eq 0
check "the run's factory.yaml has that implementer" grep -q -E '^  implementer: \{ agent: opencode, model: openrouter/qwen/qwen3\.8-27b \}' "$W/factory.yaml"
check "it has one implementer line" test "$(grep -c 'implementer:' "$W/factory.yaml")" -eq 1
check "the reviewer is not changed" grep -q -F 'reviewer: { agent: opencode, model: openrouter/qwen/qwen3.8-27b }' "$W/factory.yaml"
check "it prints the implementer" has "smoke-real: the implementer: { agent: opencode, model: openrouter/qwen/qwen3.8-27b }"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --implementer claude-code:opus
check "claude-code with another model is accepted" grep -q -F 'implementer: { agent: claude-code, model: opus }' "$(work)/factory.yaml"
for bad in opencode qwen opencode: :sonnet scripted:x gemini:x opencode:qwen/qwen3.8-27b 'opencode:openrouter/a b' 'claude-code:a}'; do
  run "$S/ygg-smoke-real.sh" "${rargs[@]}" --implementer "$bad"
  check "--implementer '$bad' is refused" test "$rc" -eq 2
done
check "a refusal says what is allowed" has "--implementer is AGENT:MODEL"

# --- the run's tail, without --dry-run: the repair path and --clip (B-109, B-111)
# A non-dry run reaches the code after `ygg run`. run_real refuses unless every guard holds: YGG_CMD is an
# executable under this test's temp folder, the engine check is off, and the folder and the credentials file are the
# test's own (dummy values). No later edit can make it reach a real or built ygg, or the founder's credentials.
run_real() {
  case "${YGG_CMD:-}" in "$T"/*) ;; *) echo "FAIL run_real refused: YGG_CMD '${YGG_CMD:-}' is not under $T"; fail=1; return 1 ;; esac
  [ -x "$YGG_CMD" ] || { echo "FAIL run_real refused: $YGG_CMD is not executable"; fail=1; return 1; }
  [ "${YGG_ENGINE_CHECK:-}" = 0 ] || { echo "FAIL run_real refused: YGG_ENGINE_CHECK is not 0"; fail=1; return 1; }
  run "$S/ygg-smoke-real.sh" --folder "$D" --tasks "$M" --odin "$O" --env "$T/factory.env" "$@"
}
# The fake ygg: doctor and status exit 0; run writes a made-up ledger with one finding raised, fixed and closed.
FY="$T/fakeygg/ygg"; mkdir -p "$T/fakeygg"
cat >"$FY" <<'EOF2'
#!/usr/bin/env bash
[ "$1" = run ] || exit 0
while [ $# -gt 0 ]; do [ "$1" = --project ] && project="$2"; shift; done
d="$project/.factory/runs/20260101-000000-abcdef"; mkdir -p "$d"
{
  echo '{"seq":1,"event":"run_started","ygg.run.id":"20260101-000000-abcdef"}'
  echo '{"seq":2,"event":"node_finished","ygg.node.id":"build","ygg.attempt":1}'
  echo '{"seq":3,"event":"finding_raised","ygg.node.id":"build","ygg.attempt":1,"ygg.finding.id":"F1","ygg.finding.source":"review","ygg.note":"server.js:3: the port is 8080"}'
  echo '{"seq":4,"event":"node_finished","ygg.node.id":"build","ygg.attempt":2}'
  echo '{"seq":5,"event":"finding_closed","ygg.node.id":"build","ygg.attempt":2,"ygg.finding.id":"F1","ygg.finding.source":"review"}'
  echo '{"seq":6,"event":"run_finished","ygg.run.id":"20260101-000000-abcdef"}'
} >"$d/ledger.jsonl"
echo "fake ygg run"
EOF2
chmod +x "$FY"
# The fake clip.exe keeps what it is given.
mkdir -p "$T/fakeclip"; printf '#!/bin/sh\ncat >"%s"\n' "$T/clipped.txt" >"$T/fakeclip/clip.exe"; chmod +x "$T/fakeclip/clip.exe"
CLIPPATH="$T/fakeclip:$PATH"

PATH="$CLIPPATH" YGG_CMD="$FY" run_real --from-leaf "$L"
W="$(work)"
check "a run from a leaf with the fake ygg exits 0" test "$rc" -eq 0
check "the ygg that ran is the fake" has "smoke-real: ygg: $FY, modified"
check "report.txt has the ygg line" grep -q -F "smoke-real: ygg: $FY" "$W/report.txt"
check "report.txt has the repair-path line" grep -q -F "repair path: finding raised, fixed, closed (finding F1 from review" "$W/report.txt"
check "the repair-path line is printed" has "repair path: finding raised, fixed, closed"
check "without --clip nothing goes to clip.exe" test ! -e "$T/clipped.txt"
check "no credential value reaches the output" hasnt "made-up-"
check "no credential value reaches report.txt" bash -c "! grep -q made-up- '$W/report.txt'"

PATH="$CLIPPATH" YGG_CMD="$FY" run_real
W="$(work)"
check "a run without --from-leaf exits 0" test "$rc" -eq 0
check "the ygg that ran is the fake (no leaf)" has "smoke-real: ygg: $FY, modified"
check "a run without --from-leaf prints no repair-path line" hasnt "repair path"
check "and report.txt has none" bash -c "! grep -q 'repair path' '$W/report.txt'"

PATH="$CLIPPATH" YGG_CMD="$FY" run_real --from-leaf "$L" --clip
W="$(work)"
check "a run with --clip exits 0" test "$rc" -eq 0
check "the ygg that ran is the fake (clip)" has "smoke-real: ygg: $FY, modified"
check "clip.exe gets the whole report.txt" cmp -s "$T/clipped.txt" "$W/report.txt"
check "the clipboard has the ygg line" grep -q -F "smoke-real: ygg: $FY" "$T/clipped.txt"
check "the clipboard has the repair-path line" grep -q -F "repair path: finding raised, fixed, closed" "$T/clipped.txt"
check "the clipboard has the evidence" grep -q -F "# ygg evidence: run 20260101-000000-abcdef" "$T/clipped.txt"
check "it says report.txt was copied" has "(report.txt copied to the clipboard)"

# The guard itself, in a subshell so its expected refusal does not count as a failure here.
(YGG_CMD=ygg run_real) >"$T/refusal"
check "run_real refuses a YGG_CMD outside the temp folder" grep -q -F "run_real refused: YGG_CMD 'ygg' is not under" "$T/refusal"
(YGG_CMD="$FY" YGG_ENGINE_CHECK=1 run_real) >"$T/refusal"
check "run_real refuses when the engine check is on" grep -q -F "run_real refused: YGG_ENGINE_CHECK is not 0" "$T/refusal"

# --- the real odin files, when this checkout has them: the edits must match their lines
R="${YGG_REAL_ODIN:-$S/../../yggdrasil/odin}"
if [ -f "$R/testdata/smoke-grade/pack.yaml" ] && [ -f "$R/testdata/smoke-grade/factory.real.example.yaml" ]; then
  run "$S/ygg-smoke-real.sh" --folder "$D" --tasks "$M" --odin "$R" --env "$T/factory.env" --dry-run \
    --from-leaf "$S/testdata/reviewer-bench/P4" --implementer opencode:openrouter/qwen/qwen3.8-27b
  W="$(work)"
  check "real odin: the dry run exits 0" test "$rc" -eq 0
  check "real odin: the pack lists the P4 files" grep -q -F 'first_commit: [LICENSE, README.md, notes.js, server.js, start.sh]' "$W/pack/pack.yaml"
  check "real odin: the implementer is set" grep -q -F 'implementer: { agent: opencode, model: openrouter/qwen/qwen3.8-27b }' "$W/factory.yaml"
else
  echo "skip the real odin files: none at $R (set YGG_REAL_ODIN)"
fi

[ "$fail" -eq 0 ] && echo "all ygg-smoke-real tests passed"
exit "$fail"

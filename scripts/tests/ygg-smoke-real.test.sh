#!/usr/bin/env bash
# Tests for ygg-smoke-real.sh: which `ygg` it says it runs (B-111), the run from a planted-fault leaf (B-109)
# and another implementer (B-110).   scripts/tests/ygg-smoke-real.test.sh
# Each case uses a fake `ygg`, a fake `go` and made-up credentials: no model, no engine, no money. Most cases are
# --dry-run. The cases of the run's tail run without it, only through run_real, which refuses unless YGG_CMD is a
# fake in this test's temp folder.
# shellcheck disable=SC2329,SC2016 # check calls has and hasnt by name; the $ in the patterns is literal
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The whole test runs under env -i, with PATH, HOME and GOPATH in its own folder (hermetic.sh).
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$HERE/hermetic.sh"
HERMETIC_TOOLS="git python3 jq" HERMETIC_PASS="YGG_REAL_ODIN YGG_REAL_MIMIR" hermetic_enter "$@"
S="$HERE/.."
trap 'rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
# The script names its folder by the second, so each run waits for the next second.
run() {
  hermetic_path_ok "$PATH" || { echo "FAIL the test's PATH leaves its folder: $PATH"; exit 3; }
  sleep 1; "$@" >"$T/out" 2>&1; rc=$?
}
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
export HOME="$T/home"; mkdir -p "$HOME"
export YGG_ENGINE_CHECK=0 # the engine environment has its own test (ygg-engine.test.sh)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export YGG_BIND="$T/bind"; mkdir -p "$YGG_BIND"

# A made-up mimir and a made-up odin (a git repo, so the build case can name its commit).
# Its task.toml has every field odin's task loader checks, so a derived copy can be checked as the loader would.
M="$T/mimir"; mkdir -p "$M/smoke-notes/sample-suite/tests" "$M/smoke-notes/environment"
printf '# brief\n' >"$M/smoke-notes/instruction.md"
brief0="$(sha256sum "$M/smoke-notes/instruction.md" | cut -d' ' -f1)"
cat >"$M/smoke-notes/task.toml" <<EOF2
schema_version = "1.4"
artifacts = ["/app"]

[task]
name = "ouroboric-dev/smoke-notes"
version = "1.0.0"

[metadata]
# SHA-256 of instruction.md. Any change to the brief makes a new task version.
brief_sha256 = "$brief0"
suite = "v1"

[verifier]
timeout_sec = 300.0
environment_mode = "separate"

[verifier.env]
SCORE_WEIGHTS = "notes=1"
EOF2
printf 'FROM scratch\n' >"$M/smoke-notes/environment/Dockerfile"
printf '{"schema":"ygg.suite/v1","suite":"v1","scenarios":[{"id":"add a note","category":"notes","kind":"fail-to-pass"}]}\n' \
  >"$M/smoke-notes/sample-suite/tests/manifest.json"
printf '#!/bin/bash\n' >"$M/smoke-notes/sample-suite/tests/test.sh"

# task_loads TASKS_DIR SUITE_DIR ID: the checks of odin's task.Load, in its order, read from internal/task/task.go
# at odin commit 89722f4 (compare that file's history to spot drift): the id; task.toml a regular file of at most
# 64 KiB that parses; artifacts ["/app"]; task.name ending in the id; task.version of the form 1.2.3 (gungnir.ValidVersion); brief_sha256 64 lowercase hex;
# the suite name; environment_mode "separate"; timeout_sec above 0 and at most a day; verifier.env names in capitals;
# SCORE_WEIGHTS summing to 1; no retired mark for the suite; instruction.md a regular file of at most 1 MiB whose
# SHA-256 in lowercase hex is brief_sha256; the suite's tests folder with test.sh and manifest.json; and of the
# manifest: its schema, suite name, at least one scenario, the suite task.toml names, and a weight for each
# fail-to-pass category (not each scenario's own fields). It prints "loads: ID VERSION SHA256" or why it does not.
task_loads() {
  python3 -I - "$@" <<'PY'
import hashlib, json, math, os, re, stat, sys, tomllib
tasks, suites, tid = sys.argv[1:4]
def no(msg):
    print("does not load: " + msg); sys.exit(1)
def regular(p, mx):
    try: st = os.lstat(p)
    except OSError as e: no(f"{p}: {e.strerror}")
    if not stat.S_ISREG(st.st_mode): no(f"{p} is not a regular file")
    if st.st_size > mx: no(f"{p} is over {mx} bytes")
    with open(p, "rb") as fh: return fh.read()
suite_re = r"[a-z0-9][a-z0-9._-]*"
if not re.fullmatch(r"[a-z][a-z0-9-]*", tid): no(f"{tid!r} is not a task id")
d = os.path.join(tasks, tid)
try: f = tomllib.loads(regular(os.path.join(d, "task.toml"), 64 << 10).decode())
except (tomllib.TOMLDecodeError, UnicodeDecodeError) as e: no(f"task.toml does not parse: {e}")
task, meta, ver = f.get("task", {}), f.get("metadata", {}), f.get("verifier", {})
name, version, sha, suite = task.get("name", ""), task.get("version", ""), meta.get("brief_sha256", ""), meta.get("suite", "")
if f.get("artifacts") != ["/app"]: no("artifacts is not [\"/app\"]")
if name[name.rfind("/") + 1:] != tid: no(f"task.name {name!r} does not end in {tid}")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version): no(f"task.version {version!r} is not of the form 1.2.3")
if not re.fullmatch(r"[0-9a-f]{64}", sha): no(f"brief_sha256 {sha!r} is not a SHA-256 in hex")
if not re.fullmatch(suite_re, suite): no(f"metadata.suite {suite!r} is not a suite version")
if ver.get("environment_mode") != "separate": no("environment_mode is not separate")
if not 0 < float(ver.get("timeout_sec", 0)) <= 24 * 3600: no("timeout_sec is out of range")
env = ver.get("env", {})
for k in env:
    if not re.fullmatch(r"[A-Z][A-Z0-9_]*", k): no(f"verifier.env {k!r} is not in capitals")
weights, total = {}, 0.0
for part in env.get("SCORE_WEIGHTS", "").split(","):
    cat, _, num = part.partition("=")
    try: v = float(num)
    except ValueError: no(f"SCORE_WEIGHTS {part!r} is not category=weight")
    if not re.fullmatch(r"[a-z][a-z0-9-]*", cat) or math.isnan(v) or not 0 <= v <= 1 or cat in weights: no(f"SCORE_WEIGHTS {part!r}")
    weights[cat] = v; total += v
if abs(total - 1) > 1e-9: no(f"SCORE_WEIGHTS sum to {total}")
if os.path.lexists(os.path.join(d, "retired", suite)): no(f"suite {suite} is retired")
got = hashlib.sha256(regular(os.path.join(d, "instruction.md"), 1 << 20)).hexdigest()
if got != sha: no(f"instruction.md hashes to {got}, task.toml says {sha}")
tests = os.path.join(suites, tid, suite, "tests")
if not os.path.isdir(tests): no(f"no tests folder {tests}")
if not os.path.isfile(os.path.join(tests, "test.sh")): no("no test.sh")
if not os.path.lexists(os.path.join(tests, "manifest.json")): no("no manifest.json")
m = json.loads(regular(os.path.join(tests, "manifest.json"), 1 << 20))
if set(m) - {"schema", "suite", "scenarios"}: no("manifest.json has an unknown field")
if m.get("schema") != "ygg.suite/v1" or not re.fullmatch(suite_re, m.get("suite", "")) or not m.get("scenarios"): no("manifest.json is not a suite")
if m["suite"] != suite: no(f"manifest.json is of suite {m['suite']}, task.toml names {suite}")
for sc in m["scenarios"]:
    if sc.get("kind") == "fail-to-pass" and sc.get("category") not in weights: no(f"scenario {sc.get('id')!r} has no weight")
print(f"loads: {tid} {version} {sha}")
PY
}
# loads: task_loads for check, quiet when the task loads. The line is kept in $T/loads.
loads() { task_loads "$@" >"$T/loads" || { cat "$T/loads"; return 1; }; }

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
[ "$1" = env ] && [ "$2" = GOWORK ] && { printf '%s\n' "${GOWORK-}"; exit 0; }
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

# --- the stale-binary guard: a ygg from PATH must have build facts (ygg-build.sh) that name the HEAD of --odin
head12="$(git -C "$O" rev-parse --short=12 HEAD)"
facts() { printf 'format: 1\nodin: %s\nsha256: %s\n' "$2" "$(sha256sum "$1" | cut -d' ' -f1)" >"$1.build.txt"; } # BINARY ODIN_COMMIT
rargs_real=("${rargs[@]:0:${#rargs[@]}-1}") # the same without --dry-run; a refusal comes before anything runs
none_made() { [ -z "$(find "$D" -mindepth 1 -maxdepth 1 -name 'smoke-real-*' -newer "$T/out.mark" -print -quit)" ]; }
mark() { : >"$T/out.mark"; sleep 1; }
build_cmd="run: $(cd "$S" && pwd)/ygg-build.sh --yggdrasil $T" # the umbrella of --odin $O is $T
rm -f "$T/pathbin/ygg.build.txt"
PATH="$T/pathbin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "guard: a dry run with a ygg with no build facts is not refused" test "$rc" -eq 0
check "guard: it prints STALE and says to run the build script" has "smoke-real: ygg guard: STALE: the ygg at $T/pathbin/ygg has no build facts"
check "guard: the dry run gives the whole build command and says it did not refuse" has "$build_cmd (a dry run: not refused)"
mark; PATH="$T/pathbin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs_real[@]}"
check "guard: a real run with no build facts is refused (exit 2)" test "$rc" -eq 2
check "guard: the refusal gives the whole build command and names --any-ygg" bash -c "grep -q -F '$build_cmd' '$T/out' && grep -q -F -- '--any-ygg' '$T/out'"
check "guard: nothing was made or run after the refusal" bash -c "! grep -q 'ygg doctor on that config' '$T/out' && ! grep -q 'smoke-real: made' '$T/out'"
check "guard: no smoke folder was made" none_made
facts "$T/pathbin/ygg" 000000000000
PATH="$T/pathbin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs_real[@]}"
check "guard: a binary built from another commit is refused" test "$rc" -eq 2
check "guard: the refusal names both commits" has "built from odin 000000000000, but the checkout $O is at $head12"
PATH="$T/pathbin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs[@]}" --any-ygg
check "guard: --any-ygg passes a stale binary" test "$rc" -eq 0
check "guard: and says it skipped the check" has "smoke-real: ygg guard: skipped (--any-ygg)"
PATH="$T/pathbin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs_real[@]}" --any-ygg
check "guard: a real run with --any-ygg and a stale binary runs, and says it skipped the check" bash -c "[ $rc -eq 0 ] && grep -q -F 'smoke-real: ygg guard: skipped (--any-ygg)' '$T/out' && grep -q 'the run ended with exit code 0' '$T/out'"
facts "$T/pathbin/ygg" "$head12"
PATH="$T/pathbin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "guard: a binary built from odin's HEAD passes" bash -c "[ $rc -eq 0 ] && grep -q -F 'smoke-real: ygg guard: ok' '$T/out'"
check "guard: and the ygg line names the commit it was built from" has "built from odin $head12 (build facts)"
cp "$T/pathbin/ygg" "$T/ygg.keep"; printf '# rebuilt by hand\n' >>"$T/pathbin/ygg"
PATH="$T/pathbin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs_real[@]}"
check "guard: a binary changed after its facts were written is refused" bash -c "[ $rc -eq 2 ] && grep -q 'is not the binary ygg-build.sh wrote' '$T/out'"
mv "$T/ygg.keep" "$T/pathbin/ygg"
# A ygg on PATH that is a link: the facts are read beside its target, where ygg-build.sh writes them.
mkdir -p "$T/linkbin" "$T/realbin"; cp "$T/pathbin/ygg" "$T/realbin/ygg"; ln -s "$T/realbin/ygg" "$T/linkbin/ygg"
facts "$T/realbin/ygg" "$head12"
PATH="$T/linkbin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs_real[@]}"
check "guard: a link on PATH passes on the facts beside its target" bash -c "[ $rc -eq 0 ] && grep -q -F 'smoke-real: ygg guard: ok: the ygg at $T/realbin/ygg' '$T/out' && grep -q -F 'built from odin $head12 (build facts)' '$T/out'"
rm -rf "$T/linkbin" "$T/realbin"
PATH="$T/pathbin:$BASEPATH" YGG_CMD="$T/other/ygg-custom" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "guard: YGG_CMD is not guarded" bash -c "[ $rc -eq 0 ] && ! grep -q 'ygg guard' '$T/out'"
PATH="$T/gobin:$BASEPATH" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "guard: a build from --odin is not guarded" bash -c "[ $rc -eq 0 ] && ! grep -q 'ygg guard' '$T/out'"
rm -f "$T/pathbin/ygg.build.txt"

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

# --- the go.work file of the build (B-111)
PATH="$T/gobin:$BASEPATH" GOWORK="$T/ws/go.work" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "a build with GOWORK set names the go.work file" has "go.work: $T/ws/go.work"
PATH="$T/gobin:$BASEPATH" GOWORK=off run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "a build with GOWORK=off says no go.work" has "go.work: no go.work"
PATH="$T/gobin:$BASEPATH" GOWORK='' run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "a build that finds no go.work says no go.work" has "go.work: no go.work"
PATH="$T/pathbin:$BASEPATH" GOWORK="$T/ws/go.work" run "$S/ygg-smoke-real.sh" "${rargs[@]}"
check "a ygg that was not built says nothing about go.work" hasnt "go.work"

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

# --- local-models LM-T13: opencode:local/<name> with --models FILE
printf 'models: []\n' >"$T/models.yaml"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --implementer opencode:local/qwen3.8-27b --models "$T/models.yaml"
W="$(work)"
check "a local implementer with --models: exit 0" test "$rc" -eq 0
check "the config has the local implementer" grep -q -x '  implementer: { agent: opencode, model: local/qwen3.8-27b } # set by ygg-smoke-real.sh --implementer' "$W/factory.yaml"
check "the config has models.file" grep -q -x "  file: $T/models.yaml" "$W/factory.yaml"
check "the models section is the file's last" bash -c 'tail -n 2 "$1" | head -n 1 | grep -q -x "models:"' _ "$W/factory.yaml"
check "it prints the implementer" has "smoke-real: the implementer: { agent: opencode, model: local/qwen3.8-27b }"
before="$(find "$D" -maxdepth 1 -name 'smoke-real-*' | wc -l)"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --implementer opencode:local/qwen3.8-27b
check "a local role without --models is refused" test "$rc" -eq 2
check "and says --models FILE is needed" has "--models FILE"
check "and made nothing" test "$(find "$D" -maxdepth 1 -name 'smoke-real-*' | wc -l)" -eq "$before"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --models "$T/models.yaml"
check "--models with no local role is refused" test "$rc" -eq 2
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --implementer opencode:local/qwen3.8-27b --models "$T/nope.yaml"
check "a models file that is missing is refused" test "$rc" -eq 2
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --implementer opencode:local/Bad --models "$T/models.yaml"
check "a bad local name is refused" test "$rc" -eq 2
# A local implementer beside an OpenRouter reviewer still needs the OpenRouter key (the example's reviewer is on it).
printf 'CLAUDE_CODE_OAUTH_TOKEN=made-up-a\n' >"$T/env-claude"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --env "$T/env-claude" --implementer opencode:local/qwen3.8-27b --models "$T/models.yaml"
check "the OpenRouter reviewer still needs OPENROUTER_API_KEY" has "OPENROUTER_API_KEY"
# An example with no OpenRouter role: no OPENROUTER_API_KEY, and no usd cap.
O2="$T/odin2"; cp -r "$O" "$O2"
printf 'roles:\n  implementer: { agent: claude-code, model: sonnet }\n  reviewer: { agent: claude-code, model: opus }\nbudget:\n  per_run: { tokens: 400000, turns: 100, usd: 3 }\n  per_day: { tokens: 1000000, turns: 200, usd: 6 }\nsandbox:\n  engine: @ENGINE@\n  mounts:\n    - { host: @FOLDER@, engine: @BIND@ }\ngrader: { tasks_dir: @TASKS@, suite_dir: @SUITES@ }\n' \
  >"$O2/testdata/smoke-grade/factory.real.example.yaml"
run "$S/ygg-smoke-real.sh" --folder "$D" --tasks "$M" --odin "$O2" --env "$T/env-claude" --dry-run
W="$(work)"
check "no OpenRouter role: no OPENROUTER_API_KEY asked, exit 0" test "$rc" -eq 0
check "and no usd cap in the config" bash -c '! grep -q "usd:" "$1"' _ "$W/factory.yaml"
check "and the other caps stay" grep -q -x '  per_run: { tokens: 400000, turns: 100 }' "$W/factory.yaml"

# --- --brief-note: the brief is the note, a blank line, then the task's instruction (B-109). A changed brief is
# another task version, so the run builds and is graded against a derived copy of the task in the run's folder.
mkdir -p "$T/suites0/smoke-notes/v1"; cp -r "$M/smoke-notes/sample-suite/tests" "$T/suites0/smoke-notes/v1/tests"
check "the made-up task loads with its suite" loads "$M" "$T/suites0" smoke-notes
printf 'Scope: only add the health route.\n' >"$T/note.md"
cp -r "$M" "$T/mimir.before"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --brief-note "$T/note.md"
W="$(work)"
DT="$W/tasks/smoke-notes"
noted="$(printf 'Scope: only add the health route.\n\n# brief')"
check "a dry run with a note exits 0" test "$rc" -eq 0
check "the derived task folder exists" test -d "$DT"
check "its instruction.md is the note, a blank line, the instruction" bash -c "[ \"\$(cat '$DT/instruction.md')\" = '$noted' ]"
check "it keeps the task's other files" cmp -s "$M/smoke-notes/environment/Dockerfile" "$DT/environment/Dockerfile"
check "and its sample suite" cmp -s "$M/smoke-notes/sample-suite/tests/manifest.json" "$DT/sample-suite/tests/manifest.json"
noted_sha="$(sha256sum "$DT/instruction.md" | cut -d' ' -f1)"
check "its brief_sha256 is the SHA-256 of the noted instruction.md" grep -q -x -F "brief_sha256 = \"$noted_sha\"" "$DT/task.toml"
check "its version is the derived version" grep -q -x -F 'version = "1.0.1000"' "$DT/task.toml"
check "the rest of task.toml stays" bash -c "diff <(grep -v -E '^(version|brief_sha256) = |^# ' '$M/smoke-notes/task.toml') <(grep -v -E '^(version|brief_sha256) = |^# ' '$DT/task.toml')"
check "task.toml says it is derived, and from what" grep -q -F '# A derived version of smoke-notes 1.0.0, made by ygg-smoke-real.sh --brief-note' "$DT/task.toml"
check "the derived task loads as odin's loader would" loads "$W/tasks" "$W/suites" smoke-notes
check "the loader line names the new version and hash" grep -q -x -F "loads: smoke-notes 1.0.1000 $noted_sha" "$T/loads"
# The check is not vacuous: the original task.toml with the noted brief does not load.
mkdir -p "$T/tampered/smoke-notes"; cp -r "$DT/." "$T/tampered/smoke-notes/"; cp "$M/smoke-notes/task.toml" "$T/tampered/smoke-notes/task.toml"
task_loads "$T/tampered" "$W/suites" smoke-notes >"$T/loads"
check "the original task.toml with the noted brief does not load" grep -q -F "does not load: instruction.md hashes to $noted_sha, task.toml says $brief0" "$T/loads"
check "ygg run gets the derived task's instruction.md" has "--brief '$DT/instruction.md'"
check "factory.yaml's tasks_dir is the run's tasks folder" grep -q -F "tasks_dir: $W/tasks" "$W/factory.yaml"
check "factory.yaml's suite_dir stays the run's suites folder" grep -q -F "suite_dir: $W/suites" "$W/factory.yaml"
check "no separate brief.md is made" test ! -e "$W/brief.md"
check "the real instruction file is not the brief" hasnt "--brief '$M/smoke-notes/instruction.md'"
check "mimir is not changed" diff -r "$T/mimir.before" "$M"
check "it says which note was used" has "smoke-real: the brief note: $T/note.md"
check "it says the task is a derived version, with its version and hash" has "smoke-real: the task is a derived version: smoke-notes 1.0.1000 (from 1.0.0), brief_sha256 $noted_sha, in $DT"
printf 'Scope: no newline at the end' >"$T/note-nonl.md"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --brief-note "$T/note-nonl.md"
check "a note without a final newline still has a blank line before the instruction" bash -c "[ \"\$(cat '$(work)/tasks/smoke-notes/instruction.md')\" = \"\$(printf 'Scope: no newline at the end\n\n# brief')\" ]"
run "$S/ygg-smoke-real.sh" "${rargs[@]}"
W="$(work)"
check "without a note ygg run gets the instruction file" has "--brief '$M/smoke-notes/instruction.md'"
check "and tasks_dir is the task checkout" grep -q -F "tasks_dir: $M" "$W/factory.yaml"
check "and no tasks folder is made" test ! -e "$W/tasks"
check "and no brief.md is made" test ! -e "$W/brief.md"
check "and no note is named" hasnt "the brief note"
check "and no derived version is named" hasnt "derived"
# A task.toml the note cannot derive from is refused: no version, two version lines, a version not of the form 1.2.3.
for bad in nover twover badver nosha; do
  B="$T/mimir-$bad"; cp -r "$M" "$B"
  case "$bad" in
    nover) sed -i '/^version = /d' "$B/smoke-notes/task.toml" ;;
    twover) printf '[other]\nversion = "2.0.0"\n' >>"$B/smoke-notes/task.toml" ;;
    badver) sed -i 's/^version = .*/version = "1.0"/' "$B/smoke-notes/task.toml" ;;
    nosha) sed -i '/^brief_sha256 = /d' "$B/smoke-notes/task.toml" ;;
  esac
  run "$S/ygg-smoke-real.sh" --folder "$D" --tasks "$B" --odin "$O" --env "$T/factory.env" --dry-run --brief-note "$T/note.md"
  check "a task.toml with $bad is refused with a note" test "$rc" -eq 2
  check "and the refusal names task.toml ($bad)" has "task.toml"
done
run "$S/ygg-smoke-real.sh" --folder "$D" --tasks "$T/mimir-nover" --odin "$O" --env "$T/factory.env" --dry-run
check "without a note that task.toml is not read for a version" test "$rc" -eq 0
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --brief-note "$T/no-such-note.md"
check "a missing note is refused" test "$rc" -eq 2
check "and named" has "no brief note at $T/no-such-note.md"
: >"$T/note-empty.md"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --brief-note "$T/note-empty.md"
check "an empty note is refused" test "$rc" -eq 2
printf ' \n\n' >"$T/note-blank.md"
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --brief-note "$T/note-blank.md"
check "a note of blanks is refused" test "$rc" -eq 2
run "$S/ygg-smoke-real.sh" "${rargs[@]}" --brief-note
check "--brief-note without a file is a usage error" test "$rc" -eq 2

# The shipped note for P4 (the leaf whose fault is in the owner check of remove).
check "P4-note.md exists" test -s "$S/testdata/reviewer-bench/P4-note.md"
check "P4-note.md asks for GET /api/health" grep -q -F 'GET /api/health' "$S/testdata/reviewer-bench/P4-note.md"
check "P4-note.md says nothing of deletion, owners or review" bash -c "! grep -q -i -E 'delet|remove|owner|review|fault|bug' '$S/testdata/reviewer-bench/P4-note.md'"

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
while [ $# -gt 0 ]; do [ "$1" = --project ] && project="$2"; [ "$1" = --brief ] && brief="$2"; shift; done
d="$project/.factory/runs/20260101-000000-abcdef"; mkdir -p "$d"
{
  echo '{"seq":1,"event":"run_started","ygg.run.id":"20260101-000000-abcdef"}'
  echo '{"seq":2,"event":"node_finished","ygg.node.id":"build","ygg.attempt":1}'
  echo '{"seq":3,"event":"finding_raised","ygg.node.id":"build","ygg.attempt":1,"ygg.finding.id":"F1","ygg.finding.source":"review","ygg.note":"server.js:3: the port is 8080"}'
  echo '{"seq":4,"event":"node_finished","ygg.node.id":"build","ygg.attempt":2}'
  echo '{"seq":5,"event":"finding_closed","ygg.node.id":"build","ygg.attempt":2,"ygg.finding.id":"F1","ygg.finding.source":"review"}'
  echo '{"seq":6,"event":"run_finished","ygg.run.id":"20260101-000000-abcdef"}'
} >"$d/ledger.jsonl"
echo "fake ygg run, brief $brief"
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

PATH="$CLIPPATH" YGG_CMD="$FY" run_real --from-leaf "$L" --brief-note "$T/note.md"
W="$(work)"
check "a run with a note exits 0" test "$rc" -eq 0
check "report.txt names the note" grep -q -F "smoke-real: the brief note: $T/note.md" "$W/report.txt"
check "the note is printed in the terminal" has "smoke-real: the brief note: $T/note.md"
check "ygg run got the derived task's instruction.md" has "fake ygg run, brief $W/tasks/smoke-notes/instruction.md"
check "the run's factory.yaml has the run's tasks folder" grep -q -F "tasks_dir: $W/tasks" "$W/factory.yaml"
noted_sha="$(sha256sum "$W/tasks/smoke-notes/instruction.md" | cut -d' ' -f1)"
check "report.txt says the task is a derived version" grep -q -F "smoke-real: the task is a derived version: smoke-notes 1.0.1000 (from 1.0.0), brief_sha256 $noted_sha" "$W/report.txt"
check "the derived task of the run loads as odin's loader would" loads "$W/tasks" "$W/suites" smoke-notes
PATH="$CLIPPATH" YGG_CMD="$FY" run_real
W="$(work)"
check "a run without a note gives ygg run the instruction file" has "fake ygg run, brief $M/smoke-notes/instruction.md"
check "and its factory.yaml has the task checkout" grep -q -F "tasks_dir: $M" "$W/factory.yaml"
check "and report.txt names no derived version" bash -c "! grep -q 'derived' '$W/report.txt'"

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

# --- the real smoke-notes task, when this checkout has mimir: the note's derived copy must load (B-109)
RM="${YGG_REAL_MIMIR:-$S/../../mimir}"
if [ -f "$RM/smoke-notes/task.toml" ]; then
  RM="$(cd "$RM" && pwd)"
  rv="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$RM/smoke-notes/task.toml")"
  run "$S/ygg-smoke-real.sh" --folder "$D" --tasks "$RM" --odin "$O" --env "$T/factory.env" --dry-run \
    --brief-note "$S/testdata/reviewer-bench/P4-note.md"
  W="$(work)"
  check "real mimir: the dry run with the P4 note exits 0" test "$rc" -eq 0
  check "real mimir: the derived task loads as odin's loader would" loads "$W/tasks" "$W/suites" smoke-notes
  check "real mimir: the derived version is the patch plus 1000" grep -q -x -F "version = \"${rv%.*}.$((${rv##*.} + 1000))\"" "$W/tasks/smoke-notes/task.toml"
  check "real mimir: the task itself still loads" loads "$RM" "$W/suites" smoke-notes
else
  echo "skip the real smoke-notes task: none at $RM (set YGG_REAL_MIMIR)"
fi

hermetic_done
[ "$fail" -eq 0 ] && echo "all ygg-smoke-real tests passed"
exit "$fail"

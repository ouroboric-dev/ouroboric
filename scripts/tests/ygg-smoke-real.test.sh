#!/usr/bin/env bash
# Tests for ygg-smoke-real.sh: which `ygg` it says it runs (B-111).   scripts/tests/ygg-smoke-real.test.sh
# Only --dry-run is used, with a fake `ygg`, a fake `go` and made-up credentials: no model, no engine, no money.
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
O="$T/odin"; mkdir -p "$O/testdata/smoke-grade"
printf 'name: smoke-grade\n' >"$O/testdata/smoke-grade/pack.yaml"
printf 'sandbox:\n  engine: @ENGINE@\n  mounts:\n    - { host: @FOLDER@, engine: @BIND@ }\ngrader: { tasks_dir: @TASKS@, suite_dir: @SUITES@ }\n' \
  >"$O/testdata/smoke-grade/factory.real.example.yaml"
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

[ "$fail" -eq 0 ] && echo "all ygg-smoke-real tests passed"
exit "$fail"

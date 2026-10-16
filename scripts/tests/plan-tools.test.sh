#!/usr/bin/env bash
# Tests for the plan-* scripts, which author and execute implementation plans.   scripts/tests/plan-tools.test.sh
# Needs git, python3 and go on PATH. A tiny Go module (no dependencies, so no network) stands in for a
# plan's component repo, and a stub stands in for the reuse linter.
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
# run CMD...: run it, keep its output in $T/out and its exit code in $rc.
run() { "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -- "$1" "$T/out"; }
g() { git -C "$1" -c user.name=Test -c user.email=test@example.invalid "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GOWORK

# --- A reference workspace: a repo `app` with a base commit and two task commits, as plan authors keep it.
REF="$T/ref"
mkdir -p "$REF/app" "$REF/notes"
git init -q "$REF/app"
printf 'module example.test/app\n\ngo 1.21\n' > "$REF/app/go.mod"
g "$REF/app" add -A && g "$REF/app" commit -qm base
B0=$(git -C "$REF/app" rev-parse HEAD)
put() { # put FILE VERSION: write the greeting package's file in its v1 or v2 state
  local want='hello'; [ "$2" = v2 ] && want='hello, world'
  case "$1" in
    greet.go) printf 'package app\n\nfunc Greeting() string { return "%s" }\n' "$want" > "$REF/app/greet.go" ;;
    greet_test.go) printf 'package app\n\nimport "testing"\n\nfunc TestGreeting(t *testing.T) {\n\tif got := Greeting(); got != "%s" {\n\t\tt.Errorf("Greeting() = %%q", got)\n\t}\n}\n' "$want" > "$REF/app/greet_test.go" ;;
  esac
}
put greet.go v1; put greet_test.go v1
g "$REF/app" add -A && g "$REF/app" commit -qm "fx-T001 add the greeting"
C1=$(git -C "$REF/app" rev-parse HEAD)
put greet.go v2; put greet_test.go v2
g "$REF/app" add -A && g "$REF/app" commit -qm "fx-T002 greet the world"
C2=$(git -C "$REF/app" rev-parse HEAD)
git -C "$REF/app" branch -q good
g "$REF/app" switch -q -c bad
printf 'package app\n\nimport "testing"\n\nfunc TestGreeting(t *testing.T) { t.Fatal("broken on purpose") }\n' > "$REF/app/greet_test.go"
g "$REF/app" commit -qam "fx-T003 break the test"
g "$REF/app" switch -q good
printf 'app %s fx-T001\napp %s fx-T002\n' "$C1" "$C2" > "$REF/tasks.map"

# The plan's template: text around directives that pull code from the task commits.
cat > "$T/part1.md" <<'EOF'
# Plan

### Task fx-T001: add the greeting

**Files (in `app`):**
- Create: `greet.go`, `greet_test.go`

Write `greet_test.go`:

@@file fx-T001 greet_test.go go@@

and `greet.go`:

@@file fx-T001 greet.go go@@

### Task fx-T002: greet the world

**Files (in `app`):**
- Modify: `greet.go`, `greet_test.go`

Apply to `greet.go`:

@@diff fx-T002 greet.go@@

and to `greet_test.go`:

@@diff fx-T002 greet_test.go@@

Then run:

```bash
go test ./...
```
EOF

# --- plan-generate.py
run python3 -I "$S/plan-generate.py" "$REF" "$T/plan.md" "$T/part1.md"
check "generate expands file and diff directives from the task commits" \
  bash -c "[ $rc = 0 ] && grep -q 'func Greeting() string { return \"hello\" }' '$T/plan.md' && grep -q '^+func Greeting() string { return \"hello, world\" }' '$T/plan.md' && ! grep -qE '^@@(file|diff) ' '$T/plan.md'"
check "generate fences a diff as diff and a file with its language" \
  bash -c "grep -q '^\`\`\`diff' '$T/plan.md' && grep -q '^\`\`\`go' '$T/plan.md'"
head -n 11 "$T/part1.md" > "$T/short.md"
run python3 -I "$S/plan-generate.py" "$REF" "$T/short-plan.md" "$T/short.md"
check "generate refuses a plan that leaves out a file a task commit changes, and writes nothing" \
  bash -c "[ $rc != 0 ] && grep -q 'files missing from the plan' '$T/out' && [ ! -e '$T/short-plan.md' ]"
printf '### Task zz-T009: nothing\n\n@@file zz-T009 greet.go go@@\n' > "$T/unknown.md"
run python3 -I "$S/plan-generate.py" "$REF" "$T/unknown-plan.md" "$T/unknown.md"
check "generate names an unknown task id instead of crashing" \
  bash -c "[ $rc != 0 ] && grep -q 'unknown task zz-T009' '$T/out' && ! grep -q Traceback '$T/out'"

# --- plan-generate.py: the files, size and steps directives
mkdir -p "$REF/big" && git init -q "$REF/big"
printf 'module example.test/big\n\ngo 1.21\n' > "$REF/big/go.mod"
g "$REF/big" add -A && g "$REF/big" commit -qm base
seq 1 450 | sed 's/^/\/\/ line /' > "$REF/big/lines.go"
g "$REF/big" add -A && g "$REF/big" commit -qm "fx-T009 a big file"
BIG=$(git -C "$REF/big" rev-parse HEAD)
printf '== fx-T002 (app) pkgs: ./\n# example.test/app\n./greet_test.go:9:5: expected failure line\n' > "$REF/red.txt"
cat > "$T/part2.md" <<'PART'
### Task fx-T001: add the greeting

@@files fx-T001@@

Size: @@size fx-T001@@

@@steps fx-T001@@

### Task fx-T002: greet the world

@@files fx-T002@@

@@steps fx-T002@@
PART
run python3 -I "$S/plan-generate.py" "$REF" "$T/plan2.md" "$T/part2.md"
check "generate expands files, size and steps from the task commits" \
  bash -c "[ $rc = 0 ] && grep -q '^\*\*Files (in \`app\`):\*\*' '$T/plan2.md' && grep -q '^- Create: \`greet.go\`, \`greet_test.go\`' '$T/plan2.md' && grep -q '^- Modify: \`greet.go\`, \`greet_test.go\`' '$T/plan2.md' && grep -q '^Size: S (' '$T/plan2.md'"
check "steps write the tests first, show the first failure, then write the code" \
  bash -c "sed -n '/^### Task fx-T002/,\$p' '$T/plan2.md' > '$T/t2.md'; a=\$(grep -n 'Step 1:\*\* write the tests' '$T/t2.md' | head -1 | cut -d: -f1); b=\$(grep -n 'expected failure line' '$T/t2.md' | head -1 | cut -d: -f1); c=\$(grep -n 'Step 3:\*\* write the code' '$T/t2.md' | head -1 | cut -d: -f1); [ -n \"\$a\" ] && [ -n \"\$b\" ] && [ -n \"\$c\" ] && [ \"\$a\" -lt \"\$b\" ] && [ \"\$b\" -lt \"\$c\" ]"
check "steps show a changed file as a patch and a new file whole" \
  bash -c "grep -q 'Write \`greet_test.go\`:' '$T/plan2.md' && grep -q 'Apply to \`greet_test.go\`:' '$T/plan2.md' && grep -q '^\`\`\`diff' '$T/plan2.md'"
check "a task with no red.txt entry still gets a step that expects a failure" \
  bash -c "grep -q 'Expect it to fail\.' '$T/plan2.md'"
printf 'big %s fx-T009\n' "$BIG" > "$REF/tasks.map"
check "steps fence what a failing test prints as an output block" \
  bash -c "grep -q '^\`\`\`output' '$T/plan2.md'"
WORK2="$T/work2"; mkdir "$WORK2"
git clone -q "$REF/app" "$WORK2/app" && git -C "$WORK2/app" checkout -q "$B0"
run python3 -I "$S/plan-replay.py" "$T/plan2.md" "$WORK2"
check "replay leaves output blocks alone, and applies the rest of a generated plan" \
  bash -c "[ $rc = 0 ] && grep -q 'fx-T002: 2 blocks applied to app' '$T/out' && git -C '$REF/app' show $C2:greet.go | cmp -s - '$WORK2/app/greet.go'"
printf '### Task fx-T009: too big\n\n@@size fx-T009@@\n' > "$T/big.md"
run python3 -I "$S/plan-generate.py" "$REF" "$T/big-plan.md" "$T/big.md"
check "size refuses an L task, and writes nothing" \
  bash -c "[ $rc != 0 ] && grep -q 'must be split' '$T/out' && [ ! -e '$T/big-plan.md' ]"
printf 'app %s fx-T001\napp %s fx-T002\n' "$C1" "$C2" > "$REF/tasks.map"
rm -f "$REF/red.txt"

# --- plan-replay.py
WORK="$T/work"; mkdir "$WORK"
git clone -q "$REF/app" "$WORK/app" && git -C "$WORK/app" checkout -q "$B0"
run python3 -I "$S/plan-replay.py" "$T/plan.md" "$WORK"
check "replay applies each task's blocks to the repo the task names, bash blocks left out" \
  bash -c "[ $rc = 0 ] && grep -q 'fx-T001: 2 blocks applied to app' '$T/out' && grep -q 'fx-T002: 2 blocks applied to app' '$T/out'"
check "replay leaves the code the task commits left" \
  bash -c "git -C '$REF/app' show $C2:greet.go | cmp -s - '$WORK/app/greet.go' && git -C '$REF/app' show $C2:greet_test.go | cmp -s - '$WORK/app/greet_test.go'"
printf '### Task zz-T001: elsewhere\n\n**Files (in `other`):**\n- Create: `x.go`\n' > "$T/other.md"
run python3 -I "$S/plan-replay.py" "$T/other.md" "$WORK"
check "replay skips a task whose repo is not in the work directory" bash -c "[ $rc = 0 ] && grep -q 'zz-T001: skipped' '$T/out'"

# --- An SDD workspace for the executor scripts: <root>/.superpowers/sdd/<slug>/plan-path names the plan.
U="$T/umbrella"
WS="$U/.superpowers/sdd/tasks-p"
mkdir -p "$WS" "$U/docs/plans/p"
cp "$T/plan.md" "$U/docs/plans/p/tasks.md"
printf 'docs/plans/p/tasks.md\n' > "$WS/plan-path"
fresh_app() { rm -rf -- "$U/app"; git clone -q "$REF/app" "$U/app" && git -C "$U/app" checkout -q "$B0"; }
fresh_app

# --- plan-blocks.py
run python3 -I "$S/plan-blocks.py" "$WS" fx-T001
check "blocks lists a task's blocks with kind and target" \
  bash -c "[ $rc = 0 ] && grep -q 'fx-T001 in app:' '$T/out' && grep -q '0: file greet_test.go' '$T/out' && grep -q '1: file greet.go' '$T/out'"
run python3 -I "$S/plan-blocks.py" "$WS" fx-T002
check "blocks lists diff and bash blocks" bash -c "grep -q '0: diff greet.go' '$T/out' && grep -q '2: bash' '$T/out'"
run python3 -I "$S/plan-blocks.py" "$WS" fx-T001 0 1
check "blocks writes file blocks to the task's repo" \
  bash -c "[ $rc = 0 ] && git -C '$REF/app' show $C1:greet.go | cmp -s - '$U/app/greet.go'"
run python3 -I "$S/plan-blocks.py" "$WS" fx-T002 0 1
check "blocks applies diff blocks with git apply" \
  bash -c "[ $rc = 0 ] && git -C '$REF/app' show $C2:greet.go | cmp -s - '$U/app/greet.go'"
run python3 -I "$S/plan-blocks.py" "$WS" fx-T002 0
check "blocks fails loudly on a diff that does not fit" bash -c "[ $rc != 0 ] && grep -q 'did not apply' '$T/out'"
run python3 -I "$S/plan-blocks.py" "$WS" fx-T002 2
check "blocks refuses to apply a bash block" bash -c "[ $rc != 0 ] && grep -q 'bash block' '$T/out'"
run python3 -I "$S/plan-blocks.py" "$WS" fx-T099
check "blocks names a task the plan lacks" bash -c "[ $rc != 0 ] && grep -q 'no task fx-T099' '$T/out'"
run python3 -I "$S/plan-blocks.py" "$T/not-a-workspace" fx-T001
check "blocks refuses a folder that is not an SDD workspace" bash -c "[ $rc != 0 ] && grep -q 'no plan-path' '$T/out'"

# --- plan-task-start.sh
fresh_app
run "$S/plan-task-start.sh" "$WS" fx-T001 app
check "task-start writes the brief into the workspace and prints the repo's base" \
  bash -c "[ $rc = 0 ] && grep -q 'brief: $WS/task-fx-T001-brief.md' '$T/out' && grep -q \"base: $B0\" '$T/out'"
check "the brief holds its own task and no other" \
  bash -c "grep -q '^### Task fx-T001' '$WS/task-fx-T001-brief.md' && ! grep -q 'fx-T002' '$WS/task-fx-T001-brief.md'"
run "$S/plan-task-start.sh" "$WS" fx-T099 app
check "task-start exits 3 for a task the plan lacks" bash -c "[ $rc = 3 ]"
WS2="$U/.superpowers/sdd/tasks-fenced"; mkdir -p "$WS2" "$U/docs/plans/f"
printf 'docs/plans/f/tasks.md\n' > "$WS2/plan-path"
printf '### Task fx-T001: one\n\n```text\n### Task fx-T002: a heading inside a fence\n```\n\nmore of one\n\n### Task fx-T002: two\n\nsecond\n' > "$U/docs/plans/f/tasks.md"
run "$S/plan-task-start.sh" "$WS2" fx-T001 app
check "a heading inside a code fence does not end the task" \
  bash -c "grep -q 'more of one' '$WS2/task-fx-T001-brief.md' && ! grep -q '^second' '$WS2/task-fx-T001-brief.md'"

# --- plan-task-done.sh
run "$S/plan-task-done.sh" "$WS" fx-T001 app "$B0" -- echo result-line
check "task-done records a completion line when the command passes" \
  bash -c "[ $rc = 0 ] && grep -q '^Task fx-T001: complete (app commits ' '$WS/progress.md' && grep -q 'result-line' '$WS/progress.md'"
run "$S/plan-task-done.sh" "$WS" fx-T002 app "$B0" -- sh -c 'echo boom; exit 3'
check "task-done records nothing and passes the exit code on when the command fails" \
  bash -c "[ $rc = 3 ] && grep -q 'NOT recorded' '$T/out' && ! grep -q 'fx-T002' '$WS/progress.md'"
run "$S/plan-task-done.sh" "$WS" fx-T002 app "$B0" echo oops
check "task-done wants -- before the command" bash -c "[ $rc = 2 ]"

# --- plan-task-land.sh
mkdir -p "$T/bin"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/uvx"; chmod +x "$T/bin/uvx"
fresh_app
python3 -I "$S/plan-blocks.py" "$WS" fx-T001 0 1 >/dev/null && python3 -I "$S/plan-blocks.py" "$WS" fx-T002 0 1 >/dev/null
export PLAN_REFERENCE="$REF"
run env PATH="$T/bin:$PATH" "$S/plan-task-land.sh" "$WS" fx-T002 app
check "task-land reports clean checks and files equal to the reference commit" \
  bash -c "[ $rc = 0 ] && grep -q 'gofmt: clean' '$T/out' && grep -q 'test -race: ok' '$T/out' && grep -q 'reuse: ok' '$T/out' && grep -q 'same as reference $C2: 2 file(s)' '$T/out'"
printf '\n// a note\n' >> "$U/app/greet.go"
run env PATH="$T/bin:$PATH" "$S/plan-task-land.sh" "$WS" fx-T002 app
check "task-land shows a file that differs from the reference, without failing" \
  bash -c "[ $rc = 0 ] && grep -q 'DIFFERS from reference $C2: greet.go' '$T/out'"
echo 'func (' >> "$U/app/greet.go"
run env PATH="$T/bin:$PATH" "$S/plan-task-land.sh" "$WS" fx-T002 app
check "task-land exits 1 when the tests fail" bash -c "[ $rc = 1 ] && grep -q 'test -race: FAIL' '$T/out'"
fresh_app
python3 -I "$S/plan-blocks.py" "$WS" fx-T001 0 1 >/dev/null && python3 -I "$S/plan-blocks.py" "$WS" fx-T002 0 1 >/dev/null
printf '#!/bin/sh\necho "reuse: bad licence" >&2\nexit 1\n' > "$T/bin/uvx"
run env PATH="$T/bin:$PATH" "$S/plan-task-land.sh" "$WS" fx-T002 app
check "task-land exits 1 when the licence check fails" bash -c "[ $rc = 1 ] && grep -q 'reuse: FAIL' '$T/out'"
unset PLAN_REFERENCE

# --- plan-states.sh
run "$S/plan-states.sh" "$REF" app "$B0" good
check "states tests every task commit on its own" \
  bash -c "[ $rc = 0 ] && grep -q '^PASS fx-T001' '$T/out' && grep -q '^PASS fx-T002' '$T/out'"
run "$S/plan-states.sh" "$REF" app good bad
check "states reports a commit that fails and exits 1" bash -c "[ $rc = 1 ] && grep -q '^FAIL fx-T003' '$T/out'"
check "states leaves no worktree behind in the reference repo" \
  bash -c "[ \$(git -C '$REF/app' worktree list | wc -l) = 1 ]"

# --- plan-red.sh
run "$S/plan-red.sh" "$REF"
check "red shows the first failure of each task's tests against its parent commit" \
  bash -c "[ $rc = 0 ] && grep -q '== fx-T001 (app)' '$T/out' && grep -q 'undefined: Greeting' '$T/out' && grep -q '== fx-T002 (app)' '$T/out' && grep -q 'FAIL: TestGreeting' '$T/out'"
check "red leaves no worktree behind in the reference repo" \
  bash -c "[ \$(git -C '$REF/app' worktree list | wc -l) = 1 ]"

exit $fail

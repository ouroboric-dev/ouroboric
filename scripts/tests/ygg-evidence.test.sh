#!/usr/bin/env bash
# Tests for ygg-evidence.sh, ygg-smoke-loop.sh and ygg-smoke-realms.sh.   scripts/tests/ygg-evidence.test.sh
# A fake `ygg` and a fake `devcontainer` stand in for the real tools: no model, no engine, no network.
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
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
export HOME="$T/home"; mkdir -p "$HOME"

SECRET='sekret-value-0123456789'
# A fake ygg: `run` writes a ledger (with a retry line and a line that leaks the secret) and exits with
# $FAKE_RUN_RC; `status` and `doctor` print one line each; `sandbox build` prints one line.
mkdir -p "$T/bin"
cat > "$T/bin/ygg" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  status) echo "run:      $2"; echo "status:   done" ;;
  doctor) echo "OK    config: fake" ;;
  sandbox) echo "built" ;;
  run)
    while [ $# -gt 0 ]; do [ "$1" = --project ] && proj="$2"; shift; done
    id=20261017-000000-000001
    mkdir -p "$proj/.factory/runs/$id"
    {
      echo '{"seq":1,"ygg.run.id":"'$id'","event":"node_started","ygg.node.id":"hello"}'
      echo '{"seq":2,"ygg.run.id":"'$id'","event":"retry","ygg.note":"overloaded, key '"$CLAUDE_CODE_OAUTH_TOKEN"'"}'
      echo '{"seq":3,"ygg.run.id":"'$id'","event":"node_finished","ygg.node.id":"hello","gen_ai.usage.input_tokens":10}'
    } > "$proj/.factory/runs/$id/ledger.jsonl"
    echo "token is $CLAUDE_CODE_OAUTH_TOKEN and sk-or-v1-abcdefghijklmnopqrstuvwx"
    exit "${FAKE_RUN_RC:-0}" ;;
esac
EOF
printf '#!/usr/bin/env bash\necho "${FAKE_CLI_VERSION:-0.89.0}"\n' > "$T/bin/devcontainer"
chmod +x "$T/bin/ygg" "$T/bin/devcontainer"
export PATH="$T/bin:$PATH"

# --- ygg-evidence.sh on a project with a ledger.
P="$T/proj"; mkdir -p "$P/.factory/runs/r1" "$P/.factory/runs/r2"
cat > "$P/.factory/runs/r2/ledger.jsonl" <<EOF
{"seq":1,"event":"node_started","ygg.node.id":"a"}
{"seq":2,"event":"node_finished","ygg.node.id":"a","gen_ai.usage.input_tokens":7}
{"seq":3,"event":"run_paused","ygg.note":"usage limit reached, key $SECRET"}
{"seq":4,"event":"retry","ygg.note":"Bearer abcdefghijklmnopqrstuvwxyz0123"}
{"seq":5,"event":"task_blocked","ygg.task.id":"gallery-t2","ygg.note":"its loop gave up"}
{"seq":6,"event":"realm_loaded","ygg.realm.name":"smoke-api"}
{"seq":7,"event":"docs_published","ygg.node.id":"spec-docs"}
{"seq":8,"event":"node_returned","ygg.node.id":"ready"}
EOF
echo '{"seq":1,"event":"node_finished"}' > "$P/.factory/runs/r1/ledger.jsonl"
: > "$T/cfg.yaml"
export SOME_API_KEY="$SECRET"
run "$S/ygg-evidence.sh" --config "$T/cfg.yaml" "$P"
check "the newest run is the default" has "# ygg evidence: run r2"
check "status is in the report" has "status:   done"
check "doctor is in the report" has "OK    config: fake"
check "node results and pauses are in the ledger part" has '"event":"run_paused"'
check "retries are in the ledger part" has '"event":"retry"'
check "blocked tasks are in the ledger part" has '"event":"task_blocked"'
check "realms, published documents and returned refusals are in the ledger part" has '"event":"node_returned"'
check "lines of other events are left out" hasnt '"event":"node_started"'
check "an environment secret is removed" hasnt "$SECRET"
check "a bearer token is removed" hasnt "abcdefghijklmnopqrstuvwxyz0123"
check "a marker shows what was removed" has "[REDACTED]"
run "$S/ygg-evidence.sh" "$P" r1
check "a named run is used" has "# ygg evidence: run r1"
run "$S/ygg-evidence.sh" "$T/nowhere"
check "a missing project is refused" test "$rc" -eq 2
mkdir -p "$T/empty"
run "$S/ygg-evidence.sh" "$T/empty"
check "a project with no run is refused" test "$rc" -eq 2
printf 'out line 1\nout line 2 %s\n' "$SECRET" > "$T/captured.txt"
run "$S/ygg-evidence.sh" --output "$T/captured.txt" "$P"
check "a captured output is in the report, redacted" has "out line 1"
check "a secret in the captured output is removed" hasnt "$SECRET"
unset SOME_API_KEY

# --- ygg-smoke-loop.sh.
D="$T/ygg-it"; mkdir -p "$D"
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$SECRET" > "$T/factory.env"
mkdir -p "$T/bind"
export YGG_BIND="$T/bind" YGG_ODIN="$T/odin" YGG_CMD="$T/bin/ygg"
args=(--folder "$D" --env "$T/factory.env" --realm "$T/realm")
run "$S/ygg-smoke-loop.sh" "${args[@]}"
check "a missing factory.yaml is refused" test "$rc" -eq 2
touch "$D/factory.yaml"
FAKE_CLI_VERSION=0.88.0 run "$S/ygg-smoke-loop.sh" "${args[@]}"
check "a wrong devcontainer version is refused" test "$rc" -eq 2
YGG_BIND="$T/missing" run "$S/ygg-smoke-loop.sh" "${args[@]}"
check "a missing bind mount is refused" test "$rc" -eq 2
FAKE_RUN_RC=4 run "$S/ygg-smoke-loop.sh" --build "${args[@]}"
check "the exit code of the run is the script's" test "$rc" -eq 4
check "the project is made" test -f "$D/smoke-loop/umbrella.yaml"
check "the images are built on request" has "built"
check "the report is printed" has "# ygg evidence: run 20261017-000000-000001"
check "the retry line is in the report" has '"event":"retry"'
check "the credential is not in the saved report" test -z "$(grep -F -- "$SECRET" "$D/h11-report.txt")"
check "a token shape is removed from the saved report" test -z "$(grep -F -- sk-or-v1-abcdefghijklmnopqrstuvwx "$D/h11-report.txt")"
# The state a run leaves behind (.factory/ and a moved leaf pointer) is allowed; anything else is refused.
PR="$D/smoke-loop"
g() { git -C "$1" -c user.name=Test -c user.email=test@example.invalid -c protocol.file.allow=always "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git init -q -b main "$T/leaf" && g "$T/leaf" commit -q --allow-empty -m leaf
mkdir -p "$PR/repos" && g "$PR" submodule add -q "$T/leaf" repos/app && g "$PR" commit -qm "leaf repos/app"
g "$PR/repos/app" commit -q --allow-empty -m "the run's merge"
check "the test project shows the moved pointer" test "$(git -C "$PR" status --short | grep -c '^ M repos/app$')" -eq 1
FAKE_RUN_RC=0 run "$S/ygg-smoke-loop.sh" "${args[@]}"
check "the state an earlier run left (.factory/, a moved pointer) still runs" test "$rc" -eq 0
echo dirty > "$PR/dirty.txt"
run "$S/ygg-smoke-loop.sh" "${args[@]}"
check "another change is refused" test "$rc" -eq 2
check "and the refusal names the file" has "dirty.txt"

# --- ygg-smoke-realms.sh.
R="$T/ygg-realms"; mkdir -p "$R"
rargs=(--folder "$R" --env "$T/factory.env")
run "$S/ygg-smoke-realms.sh" "${rargs[@]}"
check "a missing factory.yaml is refused (realms)" test "$rc" -eq 2
printf 'mode: unattended\n' > "$R/factory.yaml"
run "$S/ygg-smoke-realms.sh" "${rargs[@]}"
check "a config with no realms section is refused" test "$rc" -eq 2
check "and the refusal says why" has "no realms section"
printf 'mode: unattended\nrealms:\n  dir: /somewhere\n' > "$R/factory.yaml"
FAKE_CLI_VERSION=0.88.0 run "$S/ygg-smoke-realms.sh" "${rargs[@]}"
check "a wrong devcontainer version is refused (realms)" test "$rc" -eq 2
YGG_BIND="$T/missing" run "$S/ygg-smoke-realms.sh" "${rargs[@]}"
check "a missing bind mount is refused (realms)" test "$rc" -eq 2
FAKE_RUN_RC=5 run "$S/ygg-smoke-realms.sh" --build "${rargs[@]}"
check "the exit code of the run is the script's (realms)" test "$rc" -eq 5
check "a project is made, with no leaf" test -f "$(ls -d "$R"/smoke-realms-*/ | head -n 1)umbrella.yaml"
check "the images of every realm are built on request" has "built"
check "the report is printed (realms)" has "# ygg evidence: run 20261017-000000-000001"
check "the credential is not in the saved realms report" test -z "$(grep -F -- "$SECRET" "$R/h13-report.txt")"
sleep 1
FAKE_RUN_RC=0 run "$S/ygg-smoke-realms.sh" "${rargs[@]}"
check "each run gets a project of its own" test "$(ls -d "$R"/smoke-realms-*/ | wc -l)" -eq 2

exit "$fail"

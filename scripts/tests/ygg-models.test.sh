#!/usr/bin/env bash
# Tests for ygg-models.sh.   scripts/tests/ygg-models.test.sh
# Fakes stand in for the tools: ygg (YGG_CMD) answers `models server|preset|image|build`; ygg-engine.sh
# (YGG_ENGINE_SH) runs the fake podman; ygg-gpu.sh (YGG_GPU_SH) is a fake; curl is a fake whose server is a few
# files. The whole test runs under env -i (hermetic.sh): no real engine, GPU or ygg is ever called.
# Each check is a condition string run by eval: $rc and the helpers are read there, so the linter cannot see them used.
# shellcheck disable=SC2016,SC2034,SC2329
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$HERE/hermetic.sh"
HERMETIC_TOOLS="python3" hermetic_enter "$@"
S="$HERE/.."
M="$S/ygg-models.sh"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
run() {
  hermetic_path_ok "$PATH" || { echo "FAIL the test's PATH leaves its folder: $PATH"; exit 3; }
  "$@" >"$T/out" 2>&1; rc=$?
}
has() { grep -q -F -- "$1" "$T/out"; }
logged() { grep -q -F -- "$1" "$T/podman.log" 2>/dev/null; }
count() { grep -c -F -- "$1" "$T/podman.log" 2>/dev/null || true; }
runline() { grep '^run ' "$T/podman.log" | head -n 1; }

W="$T/weights dir"     # a path with a space: the lines of `ygg models server` are data
ST="$T/state"
SD="$T/st"             # the fakes' state: container, running, image, network, internal, up
export FAKE_T="$T"
mkdir -p "$W" "$T/fakes" "$SD"

cat >"$T/fakes/ygg" <<'FAKE'
#!/bin/bash
echo "ygg $*" >>"$FAKE_T/ygg.log"
[ "$1" = models ] || exit 64
case "$2" in
  server) [ -f "$3" ] || { echo "ygg: $3: no such file" >&2; exit 1; }; cat "$FAKE_T/server.out" ;;
  preset) [ -f "$3" ] || exit 1; printf 'version = 1\n[qwen3.8-27b]\nmodel = /models/model.gguf\n' ;;
  image) echo "ygg-models:abc123" ;;
  build) touch "$FAKE_T/st/image" ;;
  *) exit 64 ;;
esac
FAKE
cat >"$T/engine.sh" <<'FAKE'
#!/bin/bash
# ygg-engine.sh run [--folder DIR] -- CMD...: runs the fake podman for podman, and the command for the rest
echo "engine $*" >>"$FAKE_T/engine.log"
[ "$1" = run ] || exit 64
shift
while [ "$1" != -- ]; do shift; done
shift
[ -z "$FAKE_ENGINE_DOWN" ] || { echo "ygg-engine: the engine socket is not there" >&2; exit 2; }
if [ "$1" = podman ]; then shift; exec "$FAKE_T/fakes/podman" "$@"; fi
exec "$@"
FAKE
cat >"$T/fakes/podman" <<'FAKE'
#!/bin/bash
st="$FAKE_T/st"
echo "$*" >>"$FAKE_T/podman.log"
case "$1 $2" in
  "container exists") [ -e "$st/container" ] ;;
  "image exists") [ -e "$st/image" ] ;;
  "network exists") [ -e "$st/network" ] ;;
  "network inspect") cat "$st/internal" ;;
  "network create") touch "$st/network"; echo true >"$st/internal" ;;
  "inspect -f") cat "$st/running" ;;
  "logs --tail") echo "fake log: unknown key 'bogus' in the preset" ;;
  "rm -f") rm -f "$st/container" "$st/running" "$st/up" ;;
  "stop "*) echo false >"$st/running"; rm -f "$st/up" ;;
  "rm "*) rm -f "$st/container" "$st/running" ;;
  "run -d")
    touch "$st/container"
    if [ -n "$FAKE_RUN_EXITS" ]; then echo false >"$st/running"; else echo true >"$st/running"; touch "$st/up"; fi
    echo "0123456789abcdef" ;;
  *) echo "fake podman: unexpected $*" >&2; exit 65 ;;
esac
FAKE
cat >"$T/fakes/gpu.sh" <<'FAKE'
#!/bin/bash
echo "gpu $*" >>"$FAKE_T/gpu.log"
case "$1" in
  check)
    if [ -e "$FAKE_T/gpu.state" ]; then cat "$FAKE_T/gpu.state"; echo "fix: scripts/ygg-gpu.sh setup"; exit 3; fi
    echo "gpu: NVIDIA GeForce RTX 4090 24564 MiB" ;;
  setup) rm -f "$FAKE_T/gpu.state"; echo "gpu: NVIDIA GeForce RTX 4090 24564 MiB" ;;
esac
FAKE
cat >"$T/bin/curl" <<'FAKE'
#!/bin/bash
# curl -sS -m N -o FILE -w '%{http_code}' [-X POST -H H -d BODY] URL
out="" method=GET body=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in -o) out="${args[$((i + 1))]}" ;; -X) method="${args[$((i + 1))]}" ;; -d) body="${args[$((i + 1))]}" ;; esac
done
url="${args[$((${#args[@]} - 1))]}"
echo "$method $url $body" >>"$FAKE_T/curl.log"
[ -e "$FAKE_T/st/up" ] || exit 7
case "$method $url" in
  "GET "*/models) cat "$FAKE_T/models.json" >"$out"; printf 200 ;;
  "POST "*/models/load)
    code="$(cat "$FAKE_T/load.code" 2>/dev/null || echo 200)"
    cat "$FAKE_T/load.body" >"$out" 2>/dev/null || : >"$out"
    case "$code" in 200 | 400) cp "$FAKE_T/models.after.json" "$FAKE_T/models.json" ;; esac
    printf '%s' "$code" ;;
  *) exit 64 ;;
esac
FAKE
chmod +x "$T/fakes/"* "$T/engine.sh" "$T/bin/curl"
export YGG_CMD="$T/fakes/ygg" YGG_ENGINE_SH="$T/engine.sh" YGG_GPU_SH="$T/fakes/gpu.sh"
export YGG_MODELS_POLL=0.1 YGG_MODELS_TIMEOUT=2
LIST="$T/models.yaml"; : >"$LIST"

reset() { # a clean engine, and a list that names $W
  rm -rf "${SD:?}" "${ST:?}" "${T:?}"/*.log "${T:?}/gpu.state" "${T:?}/load.code" "${T:?}/load.body"; mkdir -p "$SD" "$W"
  unset FAKE_RUN_EXITS FAKE_ENGINE_DOWN
  printf 'NAME=ygg-models\nNETWORK=ygg-models\nPORT=8089\nHOST_PORT=8088\nWEIGHTS=%s\nSTATE=%s\n' "$W" "$ST" >"$T/server.out"
  printf '{"data":[{"id":"qwen3.8-27b","status":{"value":"unloaded","preset":"version = 1\n[qwen]\nmodel = x"}}]}' >"$T/models.json"
  printf '{"data":[{"id":"qwen3.8-27b","status":{"value":"loaded","preset":"version = 1\n[qwen]\nmodel = x"}}]}' >"$T/models.after.json"
}
up() { touch "$SD/container" "$SD/up"; echo true >"$SD/running"; }

# --- start
reset; touch "$SD/image"
run bash "$M" --models "$LIST" start
check "start: exits 0 and says where the server is" eval '[ $rc = 0 ] && has "http://127.0.0.1:8088"'
check "start: podman run gets the GPU, the name, the internal network, and detaches" \
  eval 'runline | grep -q -F -- "--device nvidia.com/gpu=all" && runline | grep -q -F -- "--name ygg-models" && runline | grep -q -F -- "--network ygg-models" && runline | grep -q -F -- " -d "'
check "start: both mounts are read-only, and the weights path keeps its space" \
  eval 'runline | grep -q -F -- "-v $W:/models:ro,Z" && runline | grep -q -F -- "-v $ST:/etc/ygg-models:ro,Z"'
check "start: the only published port is 127.0.0.1:<host_port>:8080" \
  eval '[ "$(runline | grep -o -- "-p [^ ]*")" = "-p 127.0.0.1:8088:8080" ] && ! runline | grep -q -E -- "--publish|-P "'
check "start: the gate learns its port from the environment" eval 'runline | grep -q -F -- "-e YGG_MODELGATE_PORT=8089"'
check "start: the preset from ygg is in the state folder" \
  eval '[ "$(cat "$ST/preset.ini")" = "$(printf "version = 1\n[qwen3.8-27b]\nmodel = /models/model.gguf")" ]'
check "start: it reads the list with ygg models server and models preset, from the file given" \
  eval 'grep -q -F "ygg models server $LIST" "$T/ygg.log" && grep -q -F "ygg models preset $LIST" "$T/ygg.log"'
check "start: every podman call goes through ygg-engine.sh run" \
  eval '[ "$(grep -c -- "-- podman" "$T/engine.log")" = "$(wc -l <"$T/podman.log")" ]'
check "start: it checks the GPU first" eval '[ "$(head -n 1 "$T/gpu.log")" = "gpu check" ]'
check "start: the image existed, so it was not built" eval '! grep -q "models build" "$T/ygg.log"'
check "start: the image is looked up by the tag ygg models image prints" eval 'logged "image exists ygg-models:abc123"'
check "start: it creates the network, internal, when it is absent" eval 'logged "network create --internal ygg-models"'

reset
run bash "$M" --models "$LIST" start
check "start: a missing image is built with ygg models build, through the engine, before the container runs" \
  eval '[ $rc = 0 ] && grep -q "^engine run.* -- $T/fakes/ygg models build" "$T/engine.log"'
reset; touch "$SD/network" "$SD/image"; echo true >"$SD/internal"
run bash "$M" --models "$LIST" start
check "start: an existing internal network is kept" eval '[ $rc = 0 ] && ! logged "network create"'
reset; touch "$SD/network" "$SD/image"; echo false >"$SD/internal"
run bash "$M" --models "$LIST" start
check "start: a network that is not internal is refused, and nothing runs" \
  eval '[ $rc != 0 ] && has "not internal" && [ "$(count "run -d")" = 0 ]'

# a list that names no weights folder fails before any call
reset; rmdir "$W"
run bash "$M" --models "$LIST" start
check "start: a weights folder that does not exist fails before any podman, engine or GPU call" \
  eval '[ $rc != 0 ] && has "$W" && [ ! -e "$T/podman.log" ] && [ ! -e "$T/engine.log" ] && [ ! -e "$T/gpu.log" ]'
reset
run bash "$M" --models "$T/nothere.yaml" start
check "start: a list that ygg refuses stops with ygg's message, and no engine call" \
  eval '[ $rc != 0 ] && has "no such file" && [ ! -e "$T/podman.log" ]'

# the GPU
reset; touch "$SD/image"; echo "missing: stale spec" >"$T/gpu.state"
run bash "$M" --models "$LIST" start
check "start: a stale CDI spec is set up again, then the server starts" \
  eval '[ $rc = 0 ] && grep -q "^gpu setup" "$T/gpu.log" && logged "run -d"'
reset; touch "$SD/image"; echo "missing: toolkit" >"$T/gpu.state"
run bash "$M" --models "$LIST" start
check "start: any other missing GPU state stops and names ygg-gpu.sh setup" \
  eval '[ $rc != 0 ] && has "ygg-gpu.sh setup" && ! grep -q "^gpu setup" "$T/gpu.log" && [ ! -e "$T/podman.log" ]'

# a container that exits while starting
reset; touch "$SD/image"
FAKE_RUN_EXITS=1 run bash "$M" --models "$LIST" start
check "start: a container that exits while starting prints the end of its log and fails" \
  eval '[ $rc != 0 ] && has "unknown key" && logged "logs --tail"'

# already running, and a stopped one
reset; touch "$SD/image"
run bash "$M" --models "$LIST" start
: >"$T/podman.log"
run bash "$M" --models "$LIST" start
check "start: a server that already runs is left alone" eval '[ $rc = 0 ] && has "already running" && [ "$(count "run -d")" = 0 ]'
reset; touch "$SD/image" "$SD/container"; echo false >"$SD/running"
run bash "$M" --models "$LIST" start
check "start: a stopped container of that name is removed, then the server starts" \
  eval '[ $rc = 0 ] && logged "rm -f ygg-models" && logged "run -d"'

# the default list
reset; touch "$SD/image"; mkdir -p "$HOME/.config/ygg"; : >"$HOME/.config/ygg/models.yaml"
run bash "$M" start
check "the list defaults to ~/.config/ygg/models.yaml" \
  eval '[ $rc = 0 ] && grep -q -F "ygg models server $HOME/.config/ygg/models.yaml" "$T/ygg.log"'
reset; touch "$SD/image"; mkdir -p "$T/xdg/ygg"; : >"$T/xdg/ygg/models.yaml"
XDG_CONFIG_HOME="$T/xdg" run bash "$M" start
check "XDG_CONFIG_HOME moves the default list" \
  eval '[ $rc = 0 ] && grep -q -F "ygg models server $T/xdg/ygg/models.yaml" "$T/ygg.log"'

# --- status
reset
run bash "$M" --models "$LIST" status
check "status: exit 3 when the container is absent" eval '[ $rc = 3 ] && has "not running"'
reset; up
run bash "$M" --models "$LIST" status
check "status: running, nothing loaded (the body holds raw newlines in strings)" \
  eval '[ $rc = 0 ] && [ "$(cat "$T/out")" = "running on http://127.0.0.1:8088, loaded: none" ]'
cp "$T/models.after.json" "$T/models.json"
run bash "$M" --models "$LIST" status
check "status: names the loaded model" \
  eval '[ $rc = 0 ] && [ "$(cat "$T/out")" = "running on http://127.0.0.1:8088, loaded: qwen3.8-27b" ]'
rm -f "$SD/up"
run bash "$M" --models "$LIST" status
check "status: a container that is up but does not answer yet says so, and exits 0" \
  eval '[ $rc = 0 ] && has "running on http://127.0.0.1:8088, loaded: unknown"'
reset; touch "$SD/container"; echo false >"$SD/running"
run bash "$M" --models "$LIST" status
check "status: a stopped container is not running (exit 3)" eval '[ $rc = 3 ]'
reset; FAKE_ENGINE_DOWN=1 run bash "$M" --models "$LIST" status
check "status: an engine that does not answer is exit 2, not 3" eval '[ $rc = 2 ] && has "engine socket"'

# --- load
reset; up
run bash "$M" --models "$LIST" load qwen3.8-27b
check "load: posts the model and waits until it is loaded" \
  eval '[ $rc = 0 ] && grep -q -F "POST http://127.0.0.1:8088/models/load {\"model\":\"qwen3.8-27b\"}" "$T/curl.log" && has "loaded"'
cp "$T/models.after.json" "$T/models.json"; : >"$T/curl.log"
run bash "$M" --models "$LIST" load qwen3.8-27b
check "load: a model that is loaded already posts nothing" eval '[ $rc = 0 ] && ! grep -q POST "$T/curl.log"'
reset; up
echo 400 >"$T/load.code"; echo '{"error":{"message":"model is already running"}}' >"$T/load.body"
run bash "$M" --models "$LIST" load qwen3.8-27b
check "load: 400 'model is already running' is success" eval '[ $rc = 0 ]'
reset; up
echo 500 >"$T/load.code"; echo 'boom' >"$T/load.body"
run bash "$M" --models "$LIST" load qwen3.8-27b
check "load: another answer is an error with the status and the body" eval '[ $rc != 0 ] && has "500" && has boom'
run bash "$M" --models "$LIST" load nothere
check "load: a model the server does not list is an error" eval '[ $rc != 0 ] && has "does not list"'
run bash "$M" --models "$LIST" load
check "load: needs a name" eval '[ $rc = 2 ] && has usage'
reset; run bash "$M" --models "$LIST" load qwen3.8-27b
check "load: a server that is not running says to start it" eval '[ $rc != 0 ] && has "ygg-models.sh start"'
reset; up
printf '{"data":[{"id":"qwen3.8-27b","status":{"value":"unloaded","failed":true,"exit_code":1}}]}' >"$T/models.after.json"
run bash "$M" --models "$LIST" load qwen3.8-27b
check "load: a load that failed says the exit code" eval '[ $rc != 0 ] && has "exit_code 1"'

# --- stop
reset; touch "$SD/network" "$SD/image"; up
run bash "$M" --models "$LIST" stop
check "stop: stops and removes the container, and touches neither the network nor the image" \
  eval '[ $rc = 0 ] && logged "stop" && logged "rm" && [ ! -e "$SD/container" ] && ! logged "network rm" && ! logged "rmi" && ! logged "image rm" && ! logged "prune" && [ -e "$SD/network" ] && [ -e "$SD/image" ]'
reset
run bash "$M" --models "$LIST" stop
check "stop: with no container it says so and exits 0" eval '[ $rc = 0 ] && has "not running"'

# --- usage and hygiene
run bash "$M"
check "no command is a usage error" eval '[ $rc = 2 ] && has usage'
run bash "$M" frobnicate
check "an unknown command is a usage error" eval '[ $rc = 2 ] && has usage'
check "the script never sets CONTAINER_HOST, and never evals or sources the lines of ygg" \
  eval '! grep -v "^[[:space:]]*#" "$M" | grep -E "CONTAINER_HOST|\beval\b|^[[:space:]]*(source|\.)[[:space:]]"'
EX="$S/testdata/models/models.example.yaml"
check "the example list exists, and names no local path or operator" \
  eval '[ -f "$EX" ] && ! grep -E "/home/|/Users/|/mnt/|brunogbv|valerio" "$EX" && grep -q "weights: /abs/" "$EX" && grep -q "state: /abs/" "$EX"'
hermetic_done
exit $fail

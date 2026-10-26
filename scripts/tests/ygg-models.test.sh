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
# arg_pair FLAG VALUE: the run call has FLAG and then VALUE as two whole arguments (one per line in podman.args)
arg_pair() { awk -v f="$1" -v v="$2" 'prev == f && $0 == v { ok = 1 } { prev = $0 } END { exit !ok }' "$T/podman.args"; }
runline() { grep '^run ' "$T/podman.log" | head -n 1; }

W="$T/weights dir"     # a path with a space: the lines of `ygg models server` are data
ST="$T/state"
EW="/mnt/engine/weights dir"   # where the engine sees the folders (sandbox.mounts)
EST="/mnt/engine/state"
SD="$T/st"             # the fakes' state: container, running, image, network, internal, up
export FAKE_T="$T"
mkdir -p "$W" "$T/fakes" "$SD"

cat >"$T/fakes/ygg" <<'FAKE'
#!/bin/bash
echo "ygg $*" >>"$FAKE_T/ygg.log"
[ "$1" = models ] || exit 64
case "$2" in
  server) # models server --config CONFIG FILE
    [ "$3" = --config ] || { echo "ygg: models server needs --config" >&2; exit 1; }
    [ -z "$FAKE_YGG_REFUSE" ] || { echo "ygg: $FAKE_YGG_REFUSE" >&2; exit 1; }
    [ -f "$5" ] || { echo "ygg: $5: no such file" >&2; exit 1; }
    cat "$FAKE_T/server.out" ;;
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
{ printf '%s\n' "$@"; echo ---; } >>"$FAKE_T/podman.args"   # one argument per line
case "$1 $2" in
  "container ls")  # --filter name=^NAME$ matches the name exactly; FAKE_ID_CLASH lists another container's name
    [ -e "$st/container" ] && echo ygg-models
    [ -z "$FAKE_ID_CLASH" ] || echo "$FAKE_ID_CLASH"
    exit 0 ;;
  "image exists") [ -z "$FAKE_IMAGE_ERR" ] || exit 125; [ -e "$st/image" ] ;;
  "network exists") [ -e "$st/network" ] ;;
  "network inspect") cat "$st/internal" ;;
  "network create") touch "$st/network"; echo true >"$st/internal" ;;
  "container inspect") cat "$st/running" ;;
  "logs --tail") echo "fake log: unknown key 'bogus' in the preset" ;;
  "rm -f") rm -f "$st/container" "$st/running" "$st/up" ;;
  "stop "*) echo false >"$st/running"; rm -f "$st/up" ;;
  "rm "*) rm -f "$st/container" "$st/running" ;;
  "run -d")
    [ -z "$FAKE_RUN_CDI" ] || { echo "Error: setting up CDI devices: unresolvable CDI devices nvidia.com/gpu=all" >&2; exit 125; }
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
  "GET "*/props\?model=*) [ -z "$FAKE_NO_PROPS" ] || { printf 404; exit 0; }; cat "$FAKE_T/props.json" >"$out"; printf 200 ;;
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
  rm -rf "${SD:?}" "${ST:?}" "${T:?}"/*.log "${T:?}"/podman.args "${T:?}/gpu.state" "${T:?}/load.code" "${T:?}/load.body"; mkdir -p "$SD" "$W"
  rm -f "$W/chat-template.jinja"
  unset FAKE_RUN_EXITS FAKE_ENGINE_DOWN FAKE_ID_CLASH FAKE_IMAGE_ERR FAKE_YGG_REFUSE FAKE_NO_PROPS FAKE_RUN_CDI
  printf 'NAME=ygg-models\nNETWORK=ygg-models\nPORT=8089\nHOST_PORT=8088\nWEIGHTS=%s\nSTATE=%s\nENGINE_WEIGHTS=%s\nENGINE_STATE=%s\n' "$W" "$ST" "$EW" "$EST" >"$T/server.out"
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
check "start: both mounts are read-only, use the engine-side paths, and the weights path keeps its space as one argument" \
  eval 'arg_pair -v "$EW:/models:ro,Z" && arg_pair -v "$EST:/etc/ygg-models:ro,Z" && ! arg_pair -v "$W:/models:ro,Z" && arg_pair -p 127.0.0.1:8088:8080 && arg_pair -e YGG_MODELGATE_PORT=8089'
check "start: the only published port is 127.0.0.1:<host_port>:8080" \
  eval '[ "$(runline | grep -o -- "-p [^ ]*")" = "-p 127.0.0.1:8088:8080" ] && ! runline | grep -q -E -- "--publish|-P "'
check "start: the gate learns its port from the environment" eval 'runline | grep -q -F -- "-e YGG_MODELGATE_PORT=8089"'
check "start: the preset from ygg is in the state folder" \
  eval '[ "$(cat "$ST/preset.ini")" = "$(printf "version = 1\n[qwen3.8-27b]\nmodel = /models/model.gguf")" ]'
check "start: it reads the list with ygg models server and models preset, from the file given" \
  eval 'grep -q -F "ygg models server --config $HOME/ygg-it/factory.yaml $LIST" "$T/ygg.log" && grep -q -F "ygg models preset $LIST" "$T/ygg.log"'
check "start: every podman call goes through ygg-engine.sh run" \
  eval '[ "$(grep -c -- "-- podman" "$T/engine.log")" = "$(wc -l <"$T/podman.log")" ]'
check "start: it checks the GPU first" eval '[ "$(head -n 1 "$T/gpu.log")" = "gpu check --folder $HOME/ygg-it" ]'
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

# the argv of the server container: dropped capabilities, no new privileges
reset; touch "$SD/image"
run bash "$M" --models "$LIST" start
check "start: the container drops all capabilities and gets no new privileges" \
  eval 'runline | grep -q -F -- "--cap-drop=ALL" && runline | grep -q -F -- "--security-opt=no-new-privileges"'
check "start: the preset is written to the host state folder, not the engine path" eval '[ -f "$ST/preset.ini" ] && [ ! -e "$EST" ]'
reset; touch "$SD/image"
run bash "$M" --models "$LIST" --folder "$T/fdir" start
check "start --folder: ygg models server gets --config DIR/factory.yaml" eval 'grep -q -F "ygg models server --config $T/fdir/factory.yaml $LIST" "$T/ygg.log"'
reset; touch "$SD/image"; export FAKE_YGG_REFUSE="the folder $W is under no sandbox.mounts entry"
run bash "$M" --models "$LIST" start
check "start: a ygg that refuses the folders (no sandbox.mounts covers them) passes its error through, and no engine call" \
  eval '[ $rc != 0 ] && has "sandbox.mounts" && [ ! -e "$T/podman.log" ]'
unset FAKE_YGG_REFUSE
reset; touch "$SD/image"; sed -i '/^ENGINE_STATE=/d' "$T/server.out"
run bash "$M" --models "$LIST" start
check "start: a missing ENGINE_STATE line is an error" eval '[ $rc != 0 ] && has ENGINE_STATE'
reset; touch "$SD/image"; export FAKE_RUN_CDI=1
run bash "$M" --models "$LIST" start
check "start: unresolvable CDI devices names ygg-gpu.sh setup" eval '[ $rc != 0 ] && has "ygg-gpu.sh setup" && has "unresolvable CDI"'
unset FAKE_RUN_CDI

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
check "start: a server that already runs is left alone, and says to stop first to apply list changes" eval '[ $rc = 0 ] && has "already running" && has "stop first" && [ "$(count "run -d")" = 0 ]'
reset; touch "$SD/image" "$SD/container"; echo false >"$SD/running"
run bash "$M" --models "$LIST" start
check "start: a stopped container of that name is removed, then the server starts" \
  eval '[ $rc = 0 ] && logged "rm -f ygg-models" && logged "run -d"'

# the default list
reset; touch "$SD/image"; mkdir -p "$HOME/.config/ygg"; : >"$HOME/.config/ygg/models.yaml"
run bash "$M" start
check "the list defaults to ~/.config/ygg/models.yaml" \
  eval '[ $rc = 0 ] && grep -q -F "ygg models server --config $HOME/ygg-it/factory.yaml $HOME/.config/ygg/models.yaml" "$T/ygg.log"'
reset; touch "$SD/image"; mkdir -p "$T/xdg/ygg"; : >"$T/xdg/ygg/models.yaml"
XDG_CONFIG_HOME="$T/xdg" run bash "$M" start
check "XDG_CONFIG_HOME moves the default list" \
  eval '[ $rc = 0 ] && grep -q -F "ygg models server --config $HOME/ygg-it/factory.yaml $T/xdg/ygg/models.yaml" "$T/ygg.log"'

# the folder: factory.yaml names the engine; ygg models build needs it, and so do the engine and GPU scripts
reset
run bash "$M" --models "$LIST" --folder "$T/fdir" start
check "start --folder DIR: DIR goes to ygg-engine.sh, ygg-gpu.sh and ygg models build --config DIR/factory.yaml" \
  eval '[ $rc = 0 ] && ! grep -v -F -e "--folder $T/fdir" "$T/engine.log" && grep -q -F -- "--folder $T/fdir" "$T/gpu.log" && grep -q -F "models build --config $T/fdir/factory.yaml" "$T/engine.log"'
reset
run bash "$M" --models "$LIST" start
check "start without --folder: the folder defaults to ~/ygg-it, in the build too" \
  eval 'grep -q -F "models build --config $HOME/ygg-it/factory.yaml" "$T/engine.log" && grep -q -F -- "--folder $HOME/ygg-it" "$T/engine.log"'
run bash "$M" --models
check "--models with no file is a usage error" eval '[ $rc = 2 ] && has usage'
run bash "$M" --folder
check "--folder with no folder is a usage error" eval '[ $rc = 2 ] && has usage'

# reserved and odd names are refused before any call
for n in host none bridge pasta private slirp4netns ns:/proc/1/ns/net container:abc pasta:-T,80 slirp4netns:cidr=10.0.0.0/24; do
  reset; sed -i "s|^NETWORK=.*|NETWORK=$n|" "$T/server.out"
  run bash "$M" --models "$LIST" start
  check "start: the network '$n' is refused before any engine call" eval '[ $rc != 0 ] && has "$n" && [ ! -e "$T/podman.log" ] && [ ! -e "$T/engine.log" ] && [ ! -e "$T/gpu.log" ]'
done
reset; sed -i "s|^NAME=.*|NAME=-rf|" "$T/server.out"
run bash "$M" --models "$LIST" start
check "start: a name that starts with a dash is refused before any engine call" eval '[ $rc != 0 ] && [ ! -e "$T/engine.log" ]'

# exact names
reset; touch "$SD/image"; export FAKE_ID_CLASH=other
run bash "$M" --models "$LIST" start
check "start: the name is matched exactly: another container in the listing is not ours" \
  eval '[ $rc = 0 ] && logged "run -d" && ! logged "rm -f"' 
unset FAKE_ID_CLASH
reset; export FAKE_ID_CLASH=cafe0123
run bash "$M" --models "$LIST" status
check "status: a listing with only another name means absent (exit 3)" eval '[ $rc = 3 ]'
unset FAKE_ID_CLASH
check "container lookups are by exact name filter and container inspect (not a bare inspect)" \
  eval 'logged "container ls -a --filter name=^ygg-models\$ --format {{.Names}}" && ! grep -q "^inspect" "$T/podman.log"'
reset; touch "$SD/image"; export FAKE_IMAGE_ERR=1
run bash "$M" --models "$LIST" start
check "start: an engine error from image exists is an error, not a build" \
  eval '[ $rc = 2 ] && ! grep -q "models build" "$T/ygg.log" 2>/dev/null && [ "$(count "run -d")" = 0 ]'
unset FAKE_IMAGE_ERR

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

# a failed load can be asked again: the router keeps failed: true until a new attempt
reset; up
printf '{"data":[{"id":"qwen3.8-27b","status":{"value":"unloaded","failed":true,"exit_code":1}}]}' >"$T/models.json"
run bash "$M" --models "$LIST" load qwen3.8-27b
check "load: a model whose last load failed is posted again, and the retry succeeds" \
  eval '[ $rc = 0 ] && grep -q "POST .*/models/load" "$T/curl.log" && has "loaded qwen3.8-27b"'

# --- template
TPL_OLD="{{- raise_exception('System message must be at the beginning.') }}"
mkprops() { python3 -I -c 'import json,sys; print(json.dumps({"chat_template": sys.argv[1]}))' "$1" >"$T/props.json"; }
reset; up; cp "$T/models.after.json" "$T/models.json"
mkprops "A
{%- if x %}
$TPL_OLD
{%- endif %}
B"
run bash "$M" --models "$LIST" template qwen3.8-27b
check "template: asks the server for /props?model=NAME" eval '[ $rc = 0 ] && grep -q -F "GET http://127.0.0.1:8088/props?model=qwen3.8-27b" "$T/curl.log"'
check "template: saves the fixed template in the host weights folder, with the system turn in place of the raise" \
  eval '[ -f "$W/chat-template.jinja" ] && ! grep -q "System message must be" "$W/chat-template.jinja" && grep -q -F "<|im_start|>system" "$W/chat-template.jinja" && head -n 1 "$W/chat-template.jinja" | grep -qx A'
check "template: no temporary file is left, and it tells to uncomment chat-template-file, then stop and start" \
  eval '! ls "$W" | grep -q tmp && has chat-template-file && has "ygg-models.sh stop" && has "ygg-models.sh start"'
reset; up; cp "$T/models.after.json" "$T/models.json"; mkprops "no such line here"
run bash "$M" --models "$LIST" template qwen3.8-27b
check "template: a template without the line is refused, and nothing is saved" eval '[ $rc != 0 ] && has "did not find" && [ ! -e "$W/chat-template.jinja" ]'
reset; up; cp "$T/models.after.json" "$T/models.json"; mkprops "A {{- '<|im_start|>system\\n' + content + '<|im_end|>\\n' }} B"
run bash "$M" --models "$LIST" template qwen3.8-27b
check "template: a template that has the fix already says so, exits 0 and saves nothing" eval '[ $rc = 0 ] && has "already in place" && [ ! -e "$W/chat-template.jinja" ]'
reset; up; cp "$T/models.after.json" "$T/models.json"; mkprops "$TPL_OLD $TPL_OLD"
run bash "$M" --models "$LIST" template qwen3.8-27b
check "template: a line found twice is refused" eval '[ $rc != 0 ] && has "did not find" && [ ! -e "$W/chat-template.jinja" ]'
reset; up; mkprops "$TPL_OLD"
run bash "$M" --models "$LIST" template qwen3.8-27b
check "template: a model that is not loaded is refused with the load command" eval '[ $rc != 0 ] && has "ygg-models.sh load qwen3.8-27b" && [ ! -e "$W/chat-template.jinja" ]'
reset
run bash "$M" --models "$LIST" template qwen3.8-27b
check "template: a server that is not running says to start it" eval '[ $rc != 0 ] && has "ygg-models.sh start"'
reset; up; cp "$T/models.after.json" "$T/models.json"; mkprops "$TPL_OLD"
run bash "$M" --models "$LIST" template 'a b&c'
check "template: a name that is not plain is refused" eval '[ $rc != 0 ] && [ ! -e "$T/curl.log" ]'
run bash "$M" --models "$LIST" template
check "template: needs a name" eval '[ $rc = 2 ] && has usage'

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
  eval '[ -f "$EX" ] && ! grep -E "/home/|/Users/|/mnt/|/root/" "$EX" && ! grep -w -F -e "$(id -un)" -e "$(basename "$HOME")" "$EX" && grep -q "weights: /abs/" "$EX" && grep -q "state: /abs/" "$EX"'
check "the example list holds the MTP, memory-safe and template keys, and every args key is a valid preset key name" \
  eval 'grep -q "cache-ram: \"2048\"" "$EX" && grep -q "ctx-checkpoints: \"4\"" "$EX" && grep -q "spec-type: draft-mtp" "$EX" && grep -q "model-draft: /models/mtp.gguf" "$EX" && grep -q "n-gpu-layers-draft: all" "$EX" && grep -q "cache-type-k-draft: q8_0" "$EX" && grep -q "cache-type-v-draft: q8_0" "$EX" && grep -q "# chat-template-file: /models/chat-template.jinja" "$EX" && ! grep -E "^      [A-Za-z0-9_-]+:" "$EX" | grep -v -E "^      [a-z][a-z0-9-]*:"'
hermetic_done
exit $fail

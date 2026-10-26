#!/usr/bin/env bash
# Tests for ygg-models.sh.   scripts/tests/ygg-models.test.sh
# Fakes stand in for the tools: ygg (YGG_CMD) answers `models server|preset|sources|image|build`; ygg-engine.sh
# (YGG_ENGINE_SH) runs the fake podman; ygg-gpu.sh (YGG_GPU_SH) is a fake; curl is a fake whose server is a few
# files; hf and uvx are fakes in their own folders, put on PATH by the cases that want them. The whole test runs
# under env -i (hermetic.sh): no real engine, GPU, network or ygg is ever called. The fakes of the steps also write
# one line each to all.log, so a case can check the order of the steps.
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
  preset) [ -f "$3" ] || exit 1
    if [ -f "$FAKE_T/preset.out" ]; then cat "$FAKE_T/preset.out"; else printf 'version = 1\n[qwen3.8-27b]\nmodel = /models/model.gguf\n'; fi ;;
  sources) [ -f "$3" ] || { echo "ygg: $3: no such file" >&2; exit 1; }; cat "$FAKE_T/sources.out" 2>/dev/null; exit 0 ;;
  image) echo "ygg-models:abc123" ;;
  build) touch "$FAKE_T/st/image"; echo build >>"$FAKE_T/all.log" ;;
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
    case "$5" in   # --filter network=NAME: the server when it exists, and FAKE_NET_USERS
      network=*) [ -e "$st/container" ] && echo ygg-models; [ -z "$FAKE_NET_USERS" ] || printf '%s\n' $FAKE_NET_USERS; exit 0 ;;
    esac
    [ -e "$st/container" ] && echo ygg-models
    [ -z "$FAKE_ID_CLASH" ] || echo "$FAKE_ID_CLASH"
    exit 0 ;;
  "image exists") [ -z "$FAKE_IMAGE_ERR" ] || exit 125; [ -e "$st/image" ] ;;
  "network exists") [ -e "$st/network" ] ;;
  "network inspect") cat "$st/internal" ;;
  "network create") touch "$st/network"; echo true >"$st/internal" ;;
  "network rm") rm -f "$st/network" ;;
  "image rm") rm -f "$st/image" ;;
  "container inspect") cat "$st/running" ;;
  "logs --tail") echo "fake log: unknown key 'bogus' in the preset" ;;
  "rm -f") rm -f "$st/container" "$st/running" "$st/up" ;;
  "stop "*) echo false >"$st/running"; rm -f "$st/up"; echo stop >>"$FAKE_T/all.log" ;;
  "rm "*) rm -f "$st/container" "$st/running" ;;
  "run -d")
    [ -z "$FAKE_RUN_CDI" ] || { echo "Error: setting up CDI devices: unresolvable CDI devices nvidia.com/gpu=all" >&2; exit 125; }
    touch "$st/container"
    echo run >>"$FAKE_T/all.log"
    # the preset each run started with, and a fresh server: nothing loaded
    cp "$FAKE_ST/preset.ini" "$FAKE_T/preset.run.$(grep -c '^run$' "$FAKE_T/all.log")" 2>/dev/null
    [ ! -f "$FAKE_T/models.unloaded.json" ] || cp "$FAKE_T/models.unloaded.json" "$FAKE_T/models.json"
    if [ -n "$FAKE_RUN_EXITS" ]; then echo false >"$st/running"; else echo true >"$st/running"; touch "$st/up"; fi
    echo "0123456789abcdef" ;;
  *) echo "fake podman: unexpected $*" >&2; exit 65 ;;
esac
FAKE
cat >"$T/fakes/gpu.sh" <<'FAKE'
#!/bin/bash
echo "gpu $*" >>"$FAKE_T/gpu.log"
if [ -n "$FAKE_LIST" ] && [ -e "$FAKE_LIST" ]; then echo "gpu $1 list=present"; else echo "gpu $1 list=absent"; fi >>"$FAKE_T/all.log"
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
  "GET "*/props\?model=*) echo props >>"$FAKE_T/all.log"; [ -z "$FAKE_NO_PROPS" ] || { printf 404; exit 0; }; cat "$FAKE_T/props.json" >"$out"; printf 200 ;;
  "GET "*/models) cat "$FAKE_T/models.json" >"$out"; printf 200 ;;
  "POST "*/models/load)
    echo load >>"$FAKE_T/all.log"
    code="$(cat "$FAKE_T/load.code" 2>/dev/null || echo 200)"
    cat "$FAKE_T/load.body" >"$out" 2>/dev/null || : >"$out"
    case "$code" in 200 | 400) cp "$FAKE_T/models.after.json" "$FAKE_T/models.json" ;; esac
    printf '%s' "$code" ;;
  *) exit 64 ;;
esac
FAKE
# hf and uvx: each logs its call to dl.log, then dl-impl writes the file (hf download REPO PATH --revision REV
# --local-dir DIR); FAKE_DL_FAIL makes the download fail and write nothing.
mkdir -p "$T/hfbin" "$T/uvxbin"
cat >"$T/dl-impl" <<'FAKE'
#!/bin/bash
[ "$1" = download ] || exit 64
repo="$2" path="$3" dir="" rev=""
shift 3
while [ $# -gt 0 ]; do
  case "$1" in --local-dir) dir="$2"; shift 2 ;; --revision) rev="$2"; shift 2 ;; *) exit 64 ;; esac
done
[ -n "$dir" ] && [ -n "$rev" ] || exit 64
[ -z "$FAKE_DL_FAIL" ] || { echo "hf: 404 Not Found" >&2; exit 1; }
if [ -n "$FAKE_LIST" ] && [ -e "$FAKE_LIST" ]; then echo "download $path list=present"; else echo "download $path list=absent"; fi >>"$FAKE_T/all.log"
mkdir -p "$(dirname "$dir/$path")"
echo "weights of $repo@$rev" >"$dir/$path"
FAKE
cat >"$T/hfbin/hf" <<'FAKE'
#!/bin/bash
echo "hf $*" >>"$FAKE_T/dl.log"
exec "$FAKE_T/dl-impl" "$@"
FAKE
cat >"$T/uvxbin/uvx" <<'FAKE'
#!/bin/bash
echo "uvx $*" >>"$FAKE_T/dl.log"
[ "$1 $2 $3" = "--from huggingface_hub hf" ] || exit 64
shift 3
exec "$FAKE_T/dl-impl" "$@"
FAKE
chmod +x "$T/fakes/"* "$T/engine.sh" "$T/bin/curl" "$T/dl-impl" "$T/hfbin/hf" "$T/uvxbin/uvx"
export YGG_CMD="$T/fakes/ygg" YGG_ENGINE_SH="$T/engine.sh" YGG_GPU_SH="$T/fakes/gpu.sh" FAKE_ST="$ST"
export YGG_MODELS_POLL=0.1 YGG_MODELS_TIMEOUT=2
LIST="$T/models.yaml"; : >"$LIST"

reset() { # a clean engine, and a list that names $W
  rm -rf "${SD:?}" "${ST:?}" "${T:?}"/*.log "${T:?}"/podman.args "${T:?}/gpu.state" "${T:?}/load.code" "${T:?}/load.body"; mkdir -p "$SD" "$W"
  rm -f "$W/chat-template.jinja" "$T/preset.out" "$T/sources.out" "$T/models.unloaded.json" "$T"/preset.run.*
  unset FAKE_RUN_EXITS FAKE_ENGINE_DOWN FAKE_ID_CLASH FAKE_IMAGE_ERR FAKE_YGG_REFUSE FAKE_NO_PROPS FAKE_RUN_CDI FAKE_NET_USERS FAKE_DL_FAIL FAKE_LIST
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

# --- setup
# The setup cases: a weights folder without a space (setup writes it into a new list, and ygg refuses a space), a list
# in a folder that does not exist yet, the founder's two files, and a preset that names the chat template.
W2="$T/w2"
NL="$T/cfg/models.yaml"
GG=Qwen3.8-27B-UD-Q4_K_M.gguf
MTP=MTP/mtp-Qwen3.8-27B-Q4_0.gguf
TPL_LINE="chat-template-file = /models/chat-template.jinja"
sreset() { # reset, then: no list, no weights, the GPU without its toolkit, no image, nothing running
  reset; rm -rf "${W2:?}" "${T:?}/cfg"; echo "missing: toolkit" >"$T/gpu.state"
  sed -i "s|^WEIGHTS=.*|WEIGHTS=$W2|" "$T/server.out"
  printf 'qwen3.8-27b unsloth/Qwen3.8-27B-GGUF main %s\nqwen3.8-27b unsloth/Qwen3.8-27B-GGUF main %s\n' "$GG" "$MTP" >"$T/sources.out"
  printf 'version = 1\n\n[qwen3.8-27b]\nmodel = /models/%s\nctx-size = 102400\n%s\nmodel-draft = /models/%s\n' "$GG" "$TPL_LINE" "$MTP" >"$T/preset.out"
  cp "$T/models.json" "$T/models.unloaded.json"
  mkprops "A
$TPL_OLD
B"
  export FAKE_LIST="$NL"
}
steps() { tr '\n' '|' <"$T/all.log" 2>/dev/null; }
lf() { sed -n "s/^  $1: \([^ ]*\).*/\1/p" "$2"; }   # lf KEY FILE: the value of a server key of a list
SETUP=(--weights "$W2" --state "$ST" --price 0.30:1.20:0.06)

sreset
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: a fresh setup exits 0" eval '[ $rc = 0 ]'
check "setup: the steps run in order: GPU check and setup (before the list), the two downloads (after it), the image, start, load, then the template, stop, start and load" \
  eval '[ "$(steps)" = "gpu check list=absent|gpu setup list=absent|download $GG list=present|download $MTP list=present|build|run|load|props|stop|run|load|" ]'
check "setup: the new list is the example with the given folders and price, and nothing else changed" \
  eval 'diff <(grep -v -E "^  (weights|state):|^    price:|^# Written by" "$S/testdata/models/models.example.yaml") <(grep -v -E "^  (weights|state):|^    price:|^# Written by" "$NL") >/dev/null && [ "$(lf weights "$NL")" = "$W2" ] && [ "$(lf state "$NL")" = "$ST" ] && grep -q -E "^    price: \{input: 0.30, output: 1.20, cache_read: 0.06\}" "$NL"'
check "setup: the list is written atomically: no temporary file is left next to it" eval '[ "$(ls -A "$T/cfg")" = models.yaml ]'
check "setup: both folders exist" eval '[ -d "$W2" ] && [ -d "$ST" ]'
check "setup: each file is downloaded with hf download REPO PATH --revision REV --local-dir WEIGHTS" \
  eval 'grep -q -x -F "hf download unsloth/Qwen3.8-27B-GGUF $GG --revision main --local-dir $W2" "$T/dl.log" && grep -q -x -F "hf download unsloth/Qwen3.8-27B-GGUF $MTP --revision main --local-dir $W2" "$T/dl.log" && [ -f "$W2/$MTP" ]'
check "setup: the first start leaves the missing chat template out of the preset; the second has it" \
  eval '! grep -q -F "$TPL_LINE" "$T/preset.run.1" && grep -q -x -F "$TPL_LINE" "$T/preset.run.2" && [ "$(cat "$ST/preset.ini")" = "$(cat "$T/preset.out")" ]'
check "setup: the template is saved in the weights folder, with the fix" \
  eval '[ -f "$W2/chat-template.jinja" ] && grep -q -F "<|im_start|>system" "$W2/chat-template.jinja"'
check "setup: the build goes through the engine with the folder's factory.yaml, and the server starts from the list given" \
  eval 'grep -q "^engine run.* -- $T/fakes/ygg models build --config $HOME/ygg-it/factory.yaml" "$T/engine.log" && grep -q -F "ygg models preset $NL" "$T/ygg.log" && grep -q -F "ygg models server --config $HOME/ygg-it/factory.yaml " "$T/ygg.log"'
check "setup: it says what each step did" \
  eval 'has "gpu: set up" && has "model list: written" && has "download: $GG: done" && has "image: built" && has "server: started" && has "load: qwen3.8-27b: loaded" && has "template: saved"'
cp "$NL" "$T/list.before"; : >"$T/all.log"; : >"$T/dl.log"; : >"$T/podman.log"; : >"$T/curl.log"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup again: exits 0, and only checks: no GPU setup, download, build, start or load" \
  eval '[ $rc = 0 ] && [ "$(steps)" = "gpu check list=present|" ] && [ ! -s "$T/dl.log" ] && ! logged "run -d" && ! logged "stop" && ! grep -q POST "$T/curl.log"'
check "setup again: the list is as it was, and the flags are said to matter only for a new list" \
  eval 'cmp -s "$NL" "$T/list.before" && has "only for a new list"'
check "setup again: every step says it is already in place" \
  eval 'has "gpu: already in place" && has "model list: already in place" && has "download: $GG: already in place" && has "download: $MTP: already in place" && has "image: already in place" && has "server: already running" && has "load: qwen3.8-27b: already loaded" && has "template: already in place"'

# --price on a new list
sreset
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup --weights "$W2" --state "$ST"
check "setup: a new list without --price refuses naming the flag, and nothing is created or called" \
  eval '[ $rc != 0 ] && has "--price" && [ ! -e "$T/cfg" ] && [ ! -e "$W2" ] && [ ! -e "$ST" ] && [ ! -e "$T/gpu.log" ] && [ ! -e "$T/podman.log" ] && [ ! -e "$T/dl.log" ]'
for bad in 0.30 abc:1 0.30:1.20:0.06:9 "1:2;rm"; do
  sreset
  PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup --weights "$W2" --state "$ST" --price "$bad"
  check "setup: --price '$bad' is refused, and nothing is created" eval '[ $rc = 2 ] && has "--price" && [ ! -e "$T/cfg" ] && [ ! -e "$T/gpu.log" ]'
done
sreset
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup --weights "$T/a b" --state "$ST" --price 1:2
check "setup: a weights folder ygg would refuse (a space) is refused before anything changes" \
  eval '[ $rc = 2 ] && has "--weights" && [ ! -e "$T/cfg" ] && [ ! -e "$T/gpu.log" ]'
sreset; export FAKE_YGG_REFUSE="the folder $W2 is under no sandbox.mounts entry"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: a new list that ygg refuses (no sandbox.mounts covers it) stops before anything changes" \
  eval '[ $rc != 0 ] && has "sandbox.mounts" && [ ! -e "$T/cfg" ] && [ ! -e "$T/gpu.log" ]'
unset FAKE_YGG_REFUSE

# the default folders
sreset; sed -i "s|^WEIGHTS=.*|WEIGHTS=$HOME/ygg-it/models/weights|; s|^STATE=.*|STATE=$HOME/ygg-it/models/state|" "$T/server.out"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup --price 1:2
check "setup: the folders default to <folder>/models/weights and <folder>/models/state, and the price without cache_read" \
  eval '[ $rc = 0 ] && [ "$(lf weights "$NL")" = "$HOME/ygg-it/models/weights" ] && [ "$(lf state "$NL")" = "$HOME/ygg-it/models/state" ] && grep -q -E "^    price: \{input: 1, output: 2\}" "$NL" && [ -d "$HOME/ygg-it/models/weights" ] && [ -d "$HOME/ygg-it/models/state" ]'
rm -rf "${HOME:?}/ygg-it"

# downloads
sreset; mkdir -p "$W2"; echo mine >"$W2/$GG"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: with one file there, only the missing one is downloaded, and the one there is untouched" \
  eval '[ $rc = 0 ] && [ "$(grep -c "^hf download" "$T/dl.log")" = 1 ] && grep -q -F " $MTP " "$T/dl.log" && [ "$(cat "$W2/$GG")" = mine ]'
sreset
PATH="$T/uvxbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: without hf on PATH, the download goes through uvx --from huggingface_hub hf" \
  eval '[ $rc = 0 ] && grep -q -x -F "uvx --from huggingface_hub hf download unsloth/Qwen3.8-27B-GGUF $GG --revision main --local-dir $W2" "$T/dl.log" && [ -f "$W2/$GG" ]'
sreset
run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: with neither hf nor uvx, it refuses naming both, before anything changes" \
  eval '[ $rc != 0 ] && has "neither hf nor uvx" && [ ! -e "$T/gpu.log" ] && [ ! -e "$T/cfg" ] && [ ! -e "$T/podman.log" ]'
sreset; export FAKE_DL_FAIL=1
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: a download that fails stops setup with hf's message" eval '[ $rc != 0 ] && has "404" && ! logged "run -d"'
unset FAKE_DL_FAIL
sreset; : >"$T/sources.out"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: a list with no download says so, and downloads nothing" eval '[ $rc = 0 ] && has "download: none" && [ ! -e "$T/dl.log" ]'
for bad in "../evil.gguf" "/etc/passwd" "a/../../b"; do
  sreset; printf 'qwen3.8-27b unsloth/Qwen3.8-27B-GGUF main %s\n' "$bad" >"$T/sources.out"
  PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
  check "setup: a source path '$bad' is refused, and nothing is downloaded or set up" eval '[ $rc != 0 ] && has "not a plain path" && [ ! -e "$T/dl.log" ] && [ ! -e "$T/gpu.log" ]'
done

# the template
sreset; mkdir -p "$W2"; echo "my template" >"$W2/chat-template.jinja"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: a template that is there is kept: no props, one start, and the preset has it" \
  eval '[ $rc = 0 ] && ! grep -q props "$T/all.log" && [ "$(grep -c "^run$" "$T/all.log")" = 1 ] && grep -q -x -F "$TPL_LINE" "$T/preset.run.1" && [ "$(cat "$W2/chat-template.jinja")" = "my template" ] && has "template: already in place"'
sreset; sed -i "/^chat-template-file/d" "$T/preset.out"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: a list that names no template: no props, one start" \
  eval '[ $rc = 0 ] && ! grep -q props "$T/all.log" && [ "$(grep -c "^run$" "$T/all.log")" = 1 ] && [ ! -e "$W2/chat-template.jinja" ] && has "template: none"'
sreset; sed -i "s|^chat-template-file = .*|chat-template-file = /models/other.jinja|" "$T/preset.out"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: a missing template of another name is refused before the download, naming it" \
  eval '[ $rc != 0 ] && has "/models/other.jinja" && [ ! -e "$T/dl.log" ] && ! logged "run -d"'
sreset; touch "$SD/image"; up; mkdir -p "$W2/MTP"; touch "$W2/$GG" "$W2/$MTP"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: a running server with the template missing is stopped, started without it, then made and started with it" \
  eval '[ $rc = 0 ] && [ "$(steps)" = "gpu check list=absent|gpu setup list=absent|stop|run|load|props|stop|run|load|" ]'

# a live run on the network: setup never stops or restarts the server under it
sreset; touch "$SD/image" "$SD/network"; echo true >"$SD/internal"; up; mkdir -p "$W2/MTP"; touch "$W2/$GG" "$W2/$MTP"
export FAKE_NET_USERS="run-live-sandbox"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: with the template missing and a run on the network, it refuses naming the run, before anything changes" \
  eval '[ $rc != 0 ] && has run-live-sandbox && has ygg-clean.sh && ! logged "stop" && ! logged "rm -f" && ! logged "run -d" && [ ! -e "$T/gpu.log" ] && [ ! -e "$T/cfg" ] && [ "$(cat "$SD/running")" = true ]'
unset FAKE_NET_USERS
sreset; mkdir -p "$W2/MTP"; touch "$W2/$GG" "$W2/$MTP" "$W2/chat-template.jinja"; touch "$SD/image" "$SD/network"; echo true >"$SD/internal"; up
cp "$T/models.after.json" "$T/models.json"; export FAKE_NET_USERS="run-live-sandbox"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: with everything in place, a run on the network does not stop setup, and nothing is stopped" \
  eval '[ $rc = 0 ] && ! logged "stop" && has "server: already running"'
unset FAKE_NET_USERS
sreset; export FAKE_NO_PROPS=1
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: a template step that fails says the server runs without the chat template, and to run setup again" \
  eval '[ $rc != 0 ] && has "runs without the chat template" && has "run setup again" && [ "$(grep -c "^run$" "$T/all.log")" = 1 ]'
unset FAKE_NO_PROPS

# a leading dash, or another character gungnir refuses, in a source
for bad in "x -bad/r main a.gguf" "x o/-r main a.gguf" "x -o/r main a.gguf" "x o/r -main a.gguf" "x o/r main -a.gguf" "x o/r main d/-a.gguf" "x o/r refs/pr/1 a.gguf" "x o/r main .hidden"; do
  sreset; echo "$bad" >"$T/sources.out"
  PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
  check "setup: the source line '$bad' is refused before anything changes" eval '[ $rc != 0 ] && [ ! -e "$T/dl.log" ] && [ ! -e "$T/gpu.log" ] && [ ! -e "$T/cfg" ]'
done

# the model to load
sreset; printf '\n[a-model]\nmodel = /models/a.gguf\nctx-size = 1\n' >>"$T/preset.out"
printf '{"data":[{"id":"a-model","status":{"value":"unloaded"}},{"id":"qwen3.8-27b","status":{"value":"unloaded"}}]}' >"$T/models.unloaded.json"
printf '{"data":[{"id":"a-model","status":{"value":"loaded"}},{"id":"qwen3.8-27b","status":{"value":"unloaded"}}]}' >"$T/models.after.json"
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}"
check "setup: it loads the first model in sorted order" \
  eval '[ $rc = 0 ] && grep -q -F "{\"model\":\"a-model\"}" "$T/curl.log" && ! grep -q -F "{\"model\":\"qwen3.8-27b\"}" "$T/curl.log"'
sreset
PATH="$T/hfbin:$PATH" run bash "$M" --models "$NL" setup "${SETUP[@]}" --model nothere
check "setup --model: a model the list does not have is refused before anything changes" \
  eval '[ $rc != 0 ] && has nothere && [ ! -e "$T/cfg" ] && [ ! -e "$T/gpu.log" ]'
run bash "$M" --models "$NL" setup --frob
check "setup: an unknown flag is a usage error" eval '[ $rc = 2 ] && has usage'

# --- clean
creset() { # a server that runs, its network and image, state files, and the two downloaded files plus others
  sreset; rm -f "${T:?}/gpu.state"; touch "$SD/network" "$SD/image"; echo true >"$SD/internal"; up
  mkdir -p "$ST" "$W2/MTP" "$T/cfg"
  for f in preset.ini allowed preset.ini.tmp .allowed-123 notes.txt; do echo x >"$ST/$f"; done
  for f in "$GG" "$MTP" chat-template.jinja extra.gguf MTP/other.gguf; do echo x >"$W2/$f"; done
  mkdir -p "$W2/.cache/huggingface/download/MTP" "$W2/.cache/other"   # hf download's state, and another cache
  echo x >"$W2/.cache/huggingface/download/MTP/mtp.metadata"; echo x >"$W2/.cache/other/keep"
  : >"$NL"
}
creset
run bash "$M" --models "$NL" clean
check "clean: stops and removes the container, then the network, then the image, saying each" \
  eval '[ $rc = 0 ] && [ "$(grep -E "^(stop |rm -f |network rm |image rm )" "$T/podman.log" | cut -d" " -f1,2 | tr "\n" "|")" = "stop -t|rm -f|network rm|image rm|" ] && has "container ygg-models: removed" && has "network ygg-models: removed" && has "image ygg-models:abc123: removed"'
check "clean: without --state or --weights, the state, the weights and the list stay" \
  eval '[ "$(ls -A "$ST" | wc -l)" = 5 ] && [ -f "$W2/$GG" ] && [ -f "$W2/$MTP" ] && [ -f "$NL" ] && [ -d "$W2/.cache/huggingface" ]'
reset; sed -i "s|^WEIGHTS=.*|WEIGHTS=$W2|" "$T/server.out"
run bash "$M" --models "$NL" clean
check "clean: with nothing there, it says so for each and removes nothing" \
  eval '[ $rc = 0 ] && ! grep -q -E "^(stop |rm |network rm |image rm )" "$T/podman.log" && has "container ygg-models: not there" && has "network ygg-models: not there" && has "image ygg-models:abc123: not there"'
creset
run bash "$M" --models "$NL" clean --state
check "clean --state: removes preset.ini, allowed and their temporary files, and keeps the folder and other files" \
  eval '[ $rc = 0 ] && [ -d "$ST" ] && [ "$(ls -A "$ST")" = notes.txt ] && [ -f "$W2/$GG" ]'
creset
run bash "$M" --models "$NL" clean --weights
check "clean --weights: removes hf download's .cache/huggingface folder, and only that path" \
  eval '[ ! -e "$W2/.cache/huggingface" ] && [ -f "$W2/.cache/other/keep" ] && [ -d "$W2/.cache" ] && has "$W2/.cache/huggingface"'
check "clean --weights: deletes the files the list downloads, and only those" \
  eval '[ $rc = 0 ] && [ ! -e "$W2/$GG" ] && [ ! -e "$W2/$MTP" ] && [ -f "$W2/extra.gguf" ] && [ -f "$W2/chat-template.jinja" ] && [ -f "$W2/MTP/other.gguf" ] && [ -d "$W2/MTP" ] && [ "$(ls -A "$ST" | wc -l)" = 5 ] && has "deleted $W2/$GG"'
creset; rm -f "${W2:?}/MTP/mtp-Qwen3.8-27B-Q4_0.gguf"
run bash "$M" --models "$NL" clean --weights --state
check "clean --weights --state: a named file already gone is fine" eval '[ $rc = 0 ] && [ ! -e "$W2/$GG" ] && [ "$(ls -A "$ST")" = notes.txt ]'
creset; printf 'qwen3.8-27b unsloth/Qwen3.8-27B-GGUF main ../outside.gguf\n' >"$T/sources.out"; echo x >"$T/outside.gguf"
run bash "$M" --models "$NL" clean --weights
check "clean --weights: a source path that leaves the weights folder is refused before anything changes" \
  eval '[ $rc != 0 ] && has "not a plain path" && [ -f "$T/outside.gguf" ] && [ -f "$W2/$GG" ] && [ -d "$W2/.cache/huggingface" ] && ! logged "stop" && ! logged "rm -f" && [ -e "$SD/container" ]'
creset; export FAKE_NET_USERS="run-abc-sandbox run-def-sandbox"
run bash "$M" --models "$NL" clean --state --weights
check "clean: another container on the network is named, and nothing is touched: the server still runs, the network and the image stay" \
  eval '[ $rc != 0 ] && has run-abc-sandbox && has run-def-sandbox && has ygg-clean.sh && ! logged "stop" && ! logged "rm -f" && ! logged "network rm" && ! logged "image rm" && [ -e "$SD/container" ] && [ "$(cat "$SD/running")" = true ] && [ -e "$SD/network" ] && [ -e "$SD/image" ] && [ "$(ls -A "$ST" | wc -l)" = 5 ] && [ -f "$W2/$GG" ]'
creset; rm -rf "${W2:?}/.cache"; mkdir -p "$T/hfhome/hub"; echo secret >"$T/hfhome/token"; ln -s "$T/hfhome" "$W2/.cache"
run bash "$M" --models "$NL" clean --weights
check "clean --weights: a symlinked .cache is refused before anything changes, and what it points to stays" \
  eval '[ $rc != 0 ] && has "symlink" && [ -f "$T/hfhome/token" ] && [ -d "$T/hfhome/hub" ] && ! logged "stop" && [ -f "$W2/$GG" ]'
creset; rm -rf "${W2:?}/.cache/huggingface"; ln -s "$T/hfhome" "$W2/.cache/huggingface"
run bash "$M" --models "$NL" clean --weights
check "clean --weights: a symlinked .cache/huggingface is refused before anything changes, and what it points to stays" \
  eval '[ $rc != 0 ] && has "symlink" && [ -f "$T/hfhome/token" ] && ! logged "stop" && [ -f "$W2/$GG" ]'
creset; rm -rf "${W2:?}/.cache/huggingface"; ln -s "$T/hfhome" "$W2/.cache/huggingface"
run bash "$M" --models "$NL" clean
check "clean without --weights: a symlinked .cache/huggingface does not matter" eval '[ $rc = 0 ] && [ -f "$T/hfhome/token" ]'
creset; export FAKE_NET_USERS="ygg-models"
run bash "$M" --models "$NL" clean
check "clean: the server itself on the network does not stop the network's removal" eval '[ $rc = 0 ] && logged "network rm ygg-models"'
unset FAKE_NET_USERS
run bash "$M" --models "$NL" clean --frob
check "clean: an unknown flag is a usage error" eval '[ $rc = 2 ] && has usage'

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
  eval 'grep -q "cache-ram: \"2048\"" "$EX" && grep -q "ctx-checkpoints: \"4\"" "$EX" && grep -q "spec-type: draft-mtp" "$EX" && grep -q "model-draft: /models/MTP/mtp-Qwen3.8-27B-Q4_0.gguf" "$EX" && grep -q "n-gpu-layers-draft: all" "$EX" && grep -q "cache-type-k-draft: q8_0" "$EX" && grep -q "cache-type-v-draft: q8_0" "$EX" && grep -q "^      chat-template-file: /models/chat-template.jinja" "$EX" && ! grep -E "^      [A-Za-z0-9_-]+:" "$EX" | grep -v -E "^      [a-z][a-z0-9-]*:"'
check "the example list names the founder's files and where they come from" \
  eval 'grep -q "^    file: Qwen3.8-27B-UD-Q4_K_M.gguf" "$EX" && grep -q "^      repo: unsloth/Qwen3.8-27B-GGUF" "$EX" && grep -q -F "files: [Qwen3.8-27B-UD-Q4_K_M.gguf, MTP/mtp-Qwen3.8-27B-Q4_0.gguf]" "$EX"'
check "the example header says to use setup, or to comment out chat-template-file until template has run" \
  eval 'sed -n "1,8p" "$EX" | grep -q "setup" && sed -n "1,8p" "$EX" | grep -q "comment out" && sed -n "1,8p" "$EX" | grep -q "chat-template-file"'
check "the example price is marked as an example" eval 'grep -E "^    price:" "$EX" | grep -q "example"'
check "the header names setup and clean and their flags" \
  eval '(for w in "setup " "clean " --weights --state --price --model; do grep -q -F -- "$w" <(sed -n "2,60p" "$M") || exit 1; done)'
hermetic_done
exit $fail

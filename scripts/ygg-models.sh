#!/usr/bin/env bash
# Start, stop and check the local model server: llama-server (router mode) and the model gate in one container, on
# the factory's engine, with the GPU (yggdrasil docs/2-engineering/specs/2026-10-25-local-models.md, 3.4 and 3.10).
#   ygg-models.sh [--models FILE] start       build the image if its tag is missing, create the internal network if it is
#                                             absent, write the preset into the state folder, run the container, wait
#                                             until the server answers
#   ygg-models.sh [--models FILE] stop        stop and remove the container; the network and the image stay
#   ygg-models.sh [--models FILE] status      print `running on http://127.0.0.1:<host_port>, loaded: <name|none>` and
#                                             exit 0; print `not running` and exit 3 when the container is absent or stopped
#   ygg-models.sh [--models FILE] load NAME   load the model and wait until it is loaded
# FILE is the operator's model list (default ${XDG_CONFIG_HOME:-$HOME/.config}/ygg/models.yaml; an example is
# scripts/testdata/models/models.example.yaml). This script never parses it: `ygg models server FILE` prints the
# server's six lines NAME=, NETWORK=, PORT=, HOST_PORT=, WEIGHTS=, STATE= (read as data, never evaluated), and
# `ygg models preset FILE` prints the preset, which `start` writes to <STATE>/preset.ini.
# The container: named NAME, on NETWORK alone (an internal network), --device nvidia.com/gpu=all, the weights at
# /models and the state at /etc/ygg-models (both read-only), 127.0.0.1:<HOST_PORT> published to 8080 (the only
# published port), and YGG_MODELGATE_PORT=<PORT> for the gate. `start` first runs ygg-gpu.sh check: a stale CDI spec
# is set up again by ygg-gpu.sh setup; any other missing state stops and names `scripts/ygg-gpu.sh setup`. The first
# image build is long (CUDA). When the container exits while starting, `start` prints the end of its log: a bad
# preset key stops the router.
# Exit codes: 0 done; 1 failed; 2 bad usage, or the engine does not answer; 3 (status) not running.
# Every engine call goes through ygg-engine.sh run, which sets the engine environment; this script never sets
# CONTAINER_HOST and never starts, stops or restarts the engine itself.
# Environment: YGG_CMD (ygg; the first on PATH), YGG_ENGINE_SH and YGG_GPU_SH (the scripts next to this one),
# YGG_MODELS_START_TIMEOUT (120 seconds for the server to answer after `start`), YGG_MODELS_TIMEOUT (300 seconds for a
# load), YGG_MODELS_POLL (1 second between polls).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ygg="${YGG_CMD:-ygg}"
engine_sh="${YGG_ENGINE_SH:-$HERE/ygg-engine.sh}"
gpu_sh="${YGG_GPU_SH:-$HERE/ygg-gpu.sh}"
start_timeout="${YGG_MODELS_START_TIMEOUT:-120}"
load_timeout="${YGG_MODELS_TIMEOUT:-300}"
poll="${YGG_MODELS_POLL:-1}"

usage() { echo "usage: ygg-models.sh [--models FILE] start|stop|status|load NAME" >&2; exit 2; }
die() { echo "ygg-models: $*" >&2; exit 1; }
list="${XDG_CONFIG_HOME:-$HOME/.config}/ygg/models.yaml"
if [ "${1:-}" = --models ]; then list="${2:?--models needs a file}"; shift 2; fi
[ $# -ge 1 ] || usage
cmd="$1"; shift
case "$cmd" in
  start | stop | status) [ $# -eq 0 ] || usage ;;
  load) [ $# -eq 1 ] || usage ;;
  *) usage ;;
esac

# The server's lines are data: read by key, never evaluated, so a path may hold spaces.
name="" network="" port="" host_port="" weights="" state=""
server_lines="$("$ygg" models server "$list")" || exit 1
while IFS='=' read -r key value; do
  case "$key" in
    NAME) name="$value" ;;
    NETWORK) network="$value" ;;
    PORT) port="$value" ;;
    HOST_PORT) host_port="$value" ;;
    WEIGHTS) weights="$value" ;;
    STATE) state="$value" ;;
  esac
done <<<"$server_lines"
for v in name network port host_port weights state; do
  [ -n "${!v}" ] || die "ygg models server $list did not print ${v^^}"
done
url="http://127.0.0.1:$host_port"

pm() { "$engine_sh" run -- podman "$@"; }

# container_state: print absent, stopped or running. An engine that does not answer ends the script with exit 2.
container_state() {
  local rc=0 running
  pm container exists "$name" >/dev/null || rc=$?
  case "$rc" in
    0) ;;
    1) echo absent; return 0 ;;
    *) exit 2 ;;
  esac
  running="$(pm inspect -f '{{.State.Running}}' "$name")" || exit 2
  if [ "$running" = true ]; then echo running; else echo stopped; fi
}

# http METHOD PATH [BODY]: sets code and body (the answer's text). A server that does not answer sets code to 000.
code="" body=""
http() {
  local f args=(-sS -m 30)
  f="$(mktemp)"
  [ "$1" = GET ] || args+=(-X "$1" -H 'Content-Type: application/json' -d "$3")
  code="$(curl "${args[@]}" -o "$f" -w '%{http_code}' "$url$2" 2>/dev/null)" || code=000
  body="$(cat "$f")"
  rm -f -- "$f"
}

# The body holds raw newlines inside strings, which a strict JSON parser refuses: parse it tolerantly.
# loaded: the name of the loaded model, or none. entry NAME: absent, or the entry's status (a word; `failed N` when
# the load failed with exit code N).
parse='
import json, sys
d = json.loads(sys.stdin.read(), strict=False)
entries = d.get("data") or []
if sys.argv[1] == "loaded":
    names = [e.get("id") for e in entries if (e.get("status") or {}).get("value") == "loaded"]
    print(names[0] if names else "none")
else:
    for e in entries:
        if e.get("id") == sys.argv[2]:
            s = e.get("status") or {}
            if s.get("failed"):
                print("failed", s.get("exit_code", "unknown"))
            else:
                print(s.get("value") or "unknown")
            break
    else:
        print("absent")
'

case "$cmd" in
  status)
    cstate="$(container_state)" || exit $?
    if [ "$cstate" != running ]; then echo "not running"; exit 3; fi
    http GET /models
    loaded=unknown
    [ "$code" != 200 ] || loaded="$(printf '%s' "$body" | python3 -I -c "$parse" loaded 2>/dev/null)" || loaded=unknown
    echo "running on $url, loaded: $loaded"
    ;;
  stop)
    cstate="$(container_state)" || exit $?
    if [ "$cstate" = absent ]; then echo "not running"; exit 0; fi
    pm stop -t 30 "$name" >/dev/null || true
    pm rm -f "$name" >/dev/null
    echo "stopped $name"
    ;;
  load)
    model="$1"
    cstate="$(container_state)" || exit $?
    [ "$cstate" = running ] || die "the model server is not running; start it: scripts/ygg-models.sh start"
    deadline=$((SECONDS + load_timeout))
    st=""
    sent=""
    while :; do
      http GET /models
      [ "$code" = 200 ] || die "model $model: GET /models answered $code at $url (start the server: scripts/ygg-models.sh start)"
      st="$(printf '%s' "$body" | python3 -I -c "$parse" entry "$model")" || die "model $model: the model list is not JSON"
      case "$st" in
        absent) die "model $model: the model server does not list it" ;;
        loaded) echo "loaded $model"; exit 0 ;;
        failed*) die "model $model: the load failed, exit_code ${st#failed }" ;;
      esac
      if [ -z "$sent" ]; then
        http POST /models/load "$(python3 -I -c 'import json,sys; print(json.dumps({"model": sys.argv[1]}, separators=(",", ":")))' "$model")"
        case "$code" in
          200) ;;
          400) case "$body" in *"model is already running"*) ;; *) die "model $model: the load request answered 400: $body" ;; esac ;;
          *) die "model $model: the load request answered $code: $body" ;;
        esac
        sent=1
      fi
      [ "$SECONDS" -lt "$deadline" ] || die "model $model: not loaded within ${load_timeout}s (status $st, wanted loaded)"
      sleep "$poll"
    done
    ;;
  start)
    [ -d "$weights" ] || die "the weights folder $weights does not exist (weights in $list); put the model files there"
    tag="$("$ygg" models image)" || exit 1
    preset="$("$ygg" models preset "$list")" || exit 1
    # The GPU: the engine resolves the CDI device before the container exists.
    rc=0
    gpu_out="$("$gpu_sh" check 2>&1)" || rc=$?
    case "$rc" in
      0) ;;
      3)
        if printf '%s\n' "$gpu_out" | grep -q 'stale spec'; then
          echo "ygg-models: the CDI spec is stale; setting it up again"
          "$gpu_sh" setup || die "scripts/ygg-gpu.sh setup failed"
        else
          printf '%s\n' "$gpu_out" >&2
          die "the GPU is not ready for the engine; run scripts/ygg-gpu.sh setup"
        fi ;;
      *) printf '%s\n' "$gpu_out" >&2; exit "$rc" ;;
    esac
    cstate="$(container_state)" || exit $?
    case "$cstate" in
      running) echo "already running on $url"; exit 0 ;;
      stopped) pm rm -f "$name" >/dev/null ;;
    esac
    if ! pm image exists "$tag" >/dev/null 2>&1; then
      echo "ygg-models: building the image $tag (the first build takes a long time: CUDA)"
      "$engine_sh" run -- "$ygg" models build || die "ygg models build failed"
    fi
    if pm network exists "$network" >/dev/null 2>&1; then
      [ "$(pm network inspect -f '{{.Internal}}' "$network")" = true ] ||
        die "the network $network exists but is not internal; remove it (podman network rm $network) or name another in $list"
    else
      pm network create --internal "$network" >/dev/null
    fi
    mkdir -p "$state"
    printf '%s\n' "$preset" >"$state/preset.ini.tmp"
    mv -f "$state/preset.ini.tmp" "$state/preset.ini"
    rc=0
    out="$(pm run -d --name "$name" --network "$network" --device nvidia.com/gpu=all \
      -v "$weights:/models:ro,Z" -v "$state:/etc/ygg-models:ro,Z" \
      -p "127.0.0.1:$host_port:8080" -e "YGG_MODELGATE_PORT=$port" "$tag" 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "$out" >&2
      case "$out" in
        *"unresolvable CDI devices"*) die "the engine cannot resolve the GPU; run scripts/ygg-gpu.sh setup" ;;
      esac
      exit 1
    fi
    deadline=$((SECONDS + start_timeout))
    while :; do
      cstate="$(container_state)" || exit $?
      if [ "$cstate" != running ]; then
        echo "ygg-models: the container exited while starting; the end of its log:" >&2
        pm logs --tail 20 "$name" >&2 || true
        exit 1
      fi
      http GET /models
      [ "$code" != 200 ] || break
      if [ "$SECONDS" -ge "$deadline" ]; then
        echo "ygg-models: the server did not answer on $url within ${start_timeout}s; the end of its log:" >&2
        pm logs --tail 20 "$name" >&2 || true
        exit 1
      fi
      sleep "$poll"
    done
    echo "ready on $url (container $name; log: podman logs $name)"
    ;;
esac

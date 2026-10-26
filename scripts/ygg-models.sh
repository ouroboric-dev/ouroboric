#!/usr/bin/env bash
# Set up, start, stop, check and clean the local model server: llama-server (router mode) and the model gate in one
# container, on the factory's engine, with the GPU (yggdrasil docs/2-engineering/specs/2026-10-25-local-models.md, 3.4
# and 3.10).
#   ygg-models.sh [--models FILE] [--folder DIR] setup [--weights DIR] [--state DIR] [--price IN:OUT[:CACHE_READ]] [--model NAME]
#                                             the whole first-time setup, safe to run again: each step is skipped when
#                                             it is in place, and prints one line that says done or already in place.
#                                             In order: ygg-gpu.sh check (and ygg-gpu.sh setup when it reports a
#                                             missing step); the list: when FILE is missing, it is written atomically
#                                             from scripts/testdata/models/models.example.yaml with the weights folder
#                                             (default DIR/models/weights), the state folder (default
#                                             DIR/models/state) and the price in dollars per million tokens, and both
#                                             folders are made; --price is required then, and a missing or bad one is
#                                             refused before anything changes; an existing FILE is used as is (the three
#                                             flags only matter for a new list); the downloads: each file of the list's
#                                             `download` (`ygg models sources`) that is missing under the weights folder,
#                                             with `hf download REPO PATH --revision REV --local-dir WEIGHTS` (hf, else
#                                             `uvx --from huggingface_hub hf`, else refused); a file that is there is
#                                             never deleted or overwritten; the image, built when its tag is missing;
#                                             start; load NAME (default: the first model of the list in sorted order).
#                                             When NAME's chat-template-file is /models/chat-template.jinja and that file
#                                             is missing under the weights folder, the first start leaves that line out
#                                             of the preset (llama-server cannot load a model whose template file is
#                                             missing), then template NAME saves it, and setup stops, starts and loads
#                                             again with the whole preset. Any other missing template file is refused
#                                             before anything changes. Everything setup refuses is checked before the
#                                             GPU step: the price, the folders, the new list (ygg reads it), the model,
#                                             the template, the download paths, and hf or uvx when a file is missing.
#   ygg-models.sh [--models FILE] [--folder DIR] clean [--state] [--weights]
#                                             decides first, then changes: while a container other than the server is
#                                             on the network (a run still uses it), it refuses and names them, and
#                                             touches nothing (the server keeps running); with --weights, a download
#                                             path that is not plain is refused the same way. Then it stops and removes
#                                             the container, removes the network, then the image, each only when it is
#                                             there, each saying what it did. --state also removes preset.ini and
#                                             allowed from the state folder, and their temporary files, never the
#                                             folder. --weights also deletes the files the list's `download` names under
#                                             the weights folder, and <weights>/.cache/huggingface (the state hf
#                                             download leaves there): never another file or folder. The list stays.
#   ygg-models.sh [--models FILE] [--folder DIR] start       build the image if its tag is missing, create the internal network if it is
#                                             absent, write the preset into the state folder, run the container, wait
#                                             until the server answers
#   ygg-models.sh [--models FILE] [--folder DIR] stop    stop and remove the container; the network and the image stay
#   ygg-models.sh [--models FILE] [--folder DIR] status  print `running on http://127.0.0.1:<host_port>, loaded: <name|none>` and
#                                             exit 0; print `not running` and exit 3 when the container is absent or stopped
#   ygg-models.sh [--models FILE] [--folder DIR] load NAME   load the model and wait until it is loaded
#   ygg-models.sh [--models FILE] [--folder DIR] template NAME   with the server running and NAME loaded, read the
#                                             model's chat template from the server (GET /props?model=NAME), replace the
#                                             line that refuses a later system message with a system turn (refused
#                                             unless that line is found exactly once) and save it as
#                                             <WEIGHTS>/chat-template.jinja, which the list's `chat-template-file:
#                                             /models/chat-template.jinja` uses at the next start (stop, then start)
# DIR (default $HOME/ygg-it) holds factory.yaml, which names the engine (sandbox.engine): it is passed to ygg-engine.sh
# and ygg-gpu.sh as --folder, and `ygg models server` and `ygg models build` read DIR/factory.yaml. The engine is a
# Podman machine that sees the host's files only through factory.yaml's `sandbox.mounts`: both the weights and the
# state folder of the list must be under a folder of those mounts (for the founder's setup, under ~/ygg-it), and
# `ygg models server --config` refuses a folder that none covers (its error names sandbox.mounts).
# FILE is the operator's model list (default ${XDG_CONFIG_HOME:-$HOME/.config}/ygg/models.yaml; an example is
# scripts/testdata/models/models.example.yaml). This script never parses it: `ygg models server --config
# DIR/factory.yaml FILE` prints the server's eight lines NAME=, NETWORK=, PORT=, HOST_PORT=, WEIGHTS=, STATE=,
# ENGINE_WEIGHTS=, ENGINE_STATE= (read as data, never evaluated; the last two are the folders as the engine sees
# them, mapped through sandbox.mounts; this script checks and writes the host ones),
# `ygg models preset FILE` prints the preset, which `start` writes to <STATE>/preset.ini (setup reads the models
# and their chat-template-file from it), and `ygg models sources FILE` prints `<model> <repo> <revision> <path>`
# per file to download (each a word; this script checks each path is relative and stays under the weights folder).
# The container: named NAME, on NETWORK alone (an internal network), --device nvidia.com/gpu=all, --cap-drop=ALL and
# --security-opt=no-new-privileges, the engine-side weights at /models and state at /etc/ygg-models (both read-only), 127.0.0.1:<HOST_PORT> published to 8080 (the only
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
example="$HERE/testdata/models/models.example.yaml"
start_timeout="${YGG_MODELS_START_TIMEOUT:-120}"
load_timeout="${YGG_MODELS_TIMEOUT:-300}"
poll="${YGG_MODELS_POLL:-1}"

usage() {
  echo "usage: ygg-models.sh [--models FILE] [--folder DIR] start|stop|status|load NAME|template NAME" >&2
  echo "       ygg-models.sh [--models FILE] [--folder DIR] setup [--weights DIR] [--state DIR] [--price IN:OUT[:CACHE_READ]] [--model NAME]" >&2
  echo "       ygg-models.sh [--models FILE] [--folder DIR] clean [--state] [--weights]" >&2
  exit 2
}
die() { echo "ygg-models: $*" >&2; exit 1; }
bad() { echo "ygg-models: $*; nothing was changed" >&2; exit 2; }
list="${XDG_CONFIG_HOME:-$HOME/.config}/ygg/models.yaml"
dir="$HOME/ygg-it"
while [ $# -gt 0 ]; do
  case "$1" in
    --models) [ $# -ge 2 ] || usage; list="$2"; shift 2 ;;
    --folder) [ $# -ge 2 ] || usage; dir="$2"; shift 2 ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || usage
cmd="$1"; shift
new_weights="" new_state="" price="" want_model="" clean_state="" clean_weights=""
case "$cmd" in
  start | stop | status) [ $# -eq 0 ] || usage ;;
  load | template) [ $# -eq 1 ] || usage ;;
  setup)
    while [ $# -gt 0 ]; do
      case "$1" in
        --weights) [ $# -ge 2 ] || usage; new_weights="$2"; shift 2 ;;
        --state) [ $# -ge 2 ] || usage; new_state="$2"; shift 2 ;;
        --price) [ $# -ge 2 ] || usage; price="$2"; shift 2 ;;
        --model) [ $# -ge 2 ] || usage; want_model="$2"; shift 2 ;;
        *) usage ;;
      esac
    done ;;
  clean)
    while [ $# -gt 0 ]; do
      case "$1" in
        --state) clean_state=1; shift ;;
        --weights) clean_weights=1; shift ;;
        *) usage ;;
      esac
    done ;;
  *) usage ;;
esac

# read_server FILE: the server's lines are data, read by key, never evaluated, so a path may hold spaces.
name="" network="" port="" host_port="" weights="" state="" engine_weights="" engine_state="" url=""
read_server() {
  local lines key value v
  lines="$("$ygg" models server --config "$dir/factory.yaml" "$1")" || exit 1
  while IFS='=' read -r key value; do
    case "$key" in
      NAME) name="$value" ;;
      NETWORK) network="$value" ;;
      PORT) port="$value" ;;
      HOST_PORT) host_port="$value" ;;
      WEIGHTS) weights="$value" ;;
      STATE) state="$value" ;;
      ENGINE_WEIGHTS) engine_weights="$value" ;;
      ENGINE_STATE) engine_state="$value" ;;
    esac
  done <<<"$lines"
  for v in name network port host_port weights state engine_weights engine_state; do
    [ -n "${!v}" ] || die "ygg models server $1 did not print ${v^^}"
  done
  url="http://127.0.0.1:$host_port"
}

# check_names: names go to podman as they are: a network such as host would ignore -p, and a name that starts with -
# is a flag.
check_names() {
  local v
  for v in "$name" "$network"; do
    [[ "$v" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "the name '$v' in $list is not a plain container or network name"
  done
  case "$network" in
    host | none | bridge | pasta | private | slirp4netns) die "the network '$network' in $list is a reserved podman network, not an internal one; name your own" ;;
  esac
}

pm() { "$engine_sh" run --folder "$dir" -- podman "$@"; }

# container_state: print absent, stopped or running. The name is matched exactly: podman also resolves a name as the
# prefix of a container ID, so a name such as `cafe` could otherwise reach another container. An engine that does not
# answer ends the script with exit 2.
container_state() {
  local names running
  names="$(pm container ls -a --filter "name=^$name\$" --format '{{.Names}}')" || exit 2
  printf '%s\n' "$names" | grep -qx -F -- "$name" || { echo absent; return 0; }
  running="$(pm container inspect -f '{{.State.Running}}' "$name")" || exit 2
  if [ "$running" = true ]; then echo running; else echo stopped; fi
}

# exists KIND REF: exit 0 when `podman KIND exists REF` says so, 1 when it says no; any other answer is an engine
# error, and ends the script with exit 2 (it is not a reason to build or create).
exists() {
  local rc=0
  pm "$1" exists "$2" >/dev/null || rc=$?
  case "$rc" in 0 | 1) return "$rc" ;; *) echo "ygg-models: podman $1 exists $2 failed (exit $rc)" >&2; exit 2 ;; esac
}

# build_image TAG: ygg models build, through the engine.
build_image() {
  echo "ygg-models: building the image $1 (the first build takes a long time: CUDA)"
  "$engine_sh" run --folder "$dir" -- "$ygg" models build --config "$dir/factory.yaml" || die "ygg models build failed"
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

# The model's template refuses a system message after the first (Claude Code sends one). This renders it as a system
# turn, and refuses a template that does not hold the refusing line exactly once. Reads /props on stdin, writes argv[1].
# A template with the fix already prints ALREADY and writes nothing, unless argv[2] is keep: then it is written as it is.
fix_template='
import json, sys
t = json.loads(sys.stdin.read(), strict=False)["chat_template"]
old = "{{- raise_exception(\x27System message must be at the beginning.\x27) }}"
new = "{{- \x27<|im_start|>system\\n\x27 + content + \x27<|im_end|>\\n\x27 }}"
if t.count(old) == 0 and t.count(new) >= 1:
    print("ALREADY")
    if sys.argv[2] == "keep":
        open(sys.argv[1], "w").write(t)
    sys.exit(0)
if t.count(old) != 1:
    sys.exit("ygg-models: did not find the line that refuses later system messages in the chat template exactly once; check the template by hand")
open(sys.argv[1], "w").write(t.replace(old, new))
'

# do_stop: stop and remove the container; sets stop_result to stopped or absent.
stop_result=""
do_stop() {
  local cstate
  cstate="$(container_state)" || exit $?
  if [ "$cstate" = absent ]; then stop_result=absent; return 0; fi
  pm stop -t 30 "$name" >/dev/null || true
  pm rm -f "$name" >/dev/null
  stop_result=stopped
}

# do_start [GPU] [NO_TEMPLATE]: start the server; sets start_result to started or running. With GPU set to skip, the GPU
# is not checked (setup checked it). With NO_TEMPLATE set, the preset leaves out `chat-template-file =
# /models/chat-template.jinja` (setup makes that file once the model is loaded).
start_result=""
do_start() {
  local gpu="${1:-check}" no_template="${2:-}" tag preset rc gpu_out cstate out deadline
  check_names
  [ -d "$weights" ] || die "the weights folder $weights does not exist (weights in $list); put the model files there"
  tag="$("$ygg" models image)" || exit 1
  preset="$("$ygg" models preset "$list")" || exit 1
  if [ -n "$no_template" ]; then
    preset="$(printf '%s\n' "$preset" | grep -v -x -F 'chat-template-file = /models/chat-template.jinja')" || true
  fi
  # The GPU: the engine resolves the CDI device before the container exists.
  if [ "$gpu" = check ]; then
    rc=0
    gpu_out="$("$gpu_sh" check --folder "$dir" 2>&1)" || rc=$?
    case "$rc" in
      0) printf '%s\n' "$gpu_out" | tail -n 1 ;;
      3)
        if printf '%s\n' "$gpu_out" | grep -qx 'missing: stale spec'; then
          echo "ygg-models: the CDI spec is stale; setting it up again"
          "$gpu_sh" setup --folder "$dir" || die "scripts/ygg-gpu.sh setup failed"
        else
          printf '%s\n' "$gpu_out" >&2
          die "the GPU is not ready for the engine; run scripts/ygg-gpu.sh setup"
        fi ;;
      *) printf '%s\n' "$gpu_out" >&2; exit "$rc" ;;
    esac
  fi
  cstate="$(container_state)" || exit $?
  case "$cstate" in
    running) start_result=running; return 0 ;;
    stopped) pm rm -f "$name" >/dev/null ;;
  esac
  exists image "$tag" || build_image "$tag"
  if exists network "$network"; then
    [ "$(pm network inspect -f '{{.Internal}}' "$network")" = true ] ||
      die "the network $network exists but is not internal; remove it (podman network rm $network) or name another in $list"
  else
    pm network create --internal "$network" >/dev/null
  fi
  mkdir -p "$state"
  printf '%s\n' "$preset" >"$state/preset.ini.tmp"
  mv -f "$state/preset.ini.tmp" "$state/preset.ini"
  rc=0
  # The engine sees the folders at their engine-side paths (sandbox.mounts); the host paths are for this script.
  # ,Z relabels the mounts for SELinux, as the sandbox driver does for its own read-only mounts.
  out="$(pm run -d --name "$name" --network "$network" --device nvidia.com/gpu=all \
    --cap-drop=ALL --security-opt=no-new-privileges \
    -v "$engine_weights:/models:ro,Z" -v "$engine_state:/etc/ygg-models:ro,Z" \
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
  start_result=started
}

# do_load NAME: load the model and wait until it is loaded; sets load_result to loaded or already.
load_result=""
do_load() {
  local model="$1" cstate deadline st="" sent=""
  cstate="$(container_state)" || exit $?
  [ "$cstate" = running ] || die "the model server is not running; start it: scripts/ygg-models.sh start"
  deadline=$((SECONDS + load_timeout))
  while :; do
    http GET /models
    [ "$code" = 200 ] || die "model $model: GET /models answered $code at $url (start the server: scripts/ygg-models.sh start)"
    st="$(printf '%s' "$body" | python3 -I -c "$parse" entry "$model")" || die "model $model: the model list is not JSON"
    case "$st" in
      absent) die "model $model: the model server does not list it" ;;
      loaded) if [ -n "$sent" ]; then load_result=loaded; else load_result=already; fi; return 0 ;;
    esac
    # The router keeps `failed: true` until a new load attempt, so a model that is not loaded is asked to load
    # (as odin's Ready does); a failure counts only after that.
    if [ -z "$sent" ]; then
      http POST /models/load "$(python3 -I -c 'import json,sys; print(json.dumps({"model": sys.argv[1]}, separators=(",", ":")))' "$model")"
      case "$code" in
        200) ;;
        400) case "$body" in *"model is already running"*) ;; *) die "model $model: the load request answered 400: $body" ;; esac ;;
        *) die "model $model: the load request answered $code: $body" ;;
      esac
      sent=1
      sleep "$poll"
      continue
    fi
    case "$st" in failed*) die "model $model: the load failed, exit_code ${st#failed }" ;; esac
    [ "$SECONDS" -lt "$deadline" ] || die "model $model: not loaded within ${load_timeout}s (status $st, wanted loaded)"
    sleep "$poll"
  done
}

# do_template NAME [keep]: save the loaded model's fixed template as <weights>/chat-template.jinja; sets template_result
# to saved, or already (the server's template has the fix; with keep, it is saved as it is).
template_result=""
do_template() {
  local model="$1" keep="${2:-}" cstate st tmp res
  [[ "$model" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "the model name '$model' is not a plain name"
  cstate="$(container_state)" || exit $?
  [ "$cstate" = running ] || die "the model server is not running; start it: scripts/ygg-models.sh start"
  [ -d "$weights" ] || die "the weights folder $weights does not exist"
  http GET /models
  [ "$code" = 200 ] || die "model $model: GET /models answered $code at $url"
  st="$(printf '%s' "$body" | python3 -I -c "$parse" entry "$model")" || die "model $model: the model list is not JSON"
  case "$st" in
    absent) die "model $model: the model server does not list it" ;;
    loaded) ;;
    *) die "model $model is not loaded (status $st); load it first: scripts/ygg-models.sh load $model" ;;
  esac
  # The router forwards GET /props?model=NAME to the loaded model's server.
  http GET "/props?model=$model"
  [ "$code" = 200 ] || die "model $model: GET /props?model=$model answered $code at $url"
  tmp="$weights/chat-template.jinja.tmp"
  res="$(printf '%s' "$body" | python3 -I -c "$fix_template" "$tmp" "${keep:-no}")" || { rm -f -- "$tmp"; exit 1; }
  if [ "$res" = ALREADY ] && [ -z "$keep" ]; then
    rm -f -- "$tmp"
    template_result=already
    return 0
  fi
  mv -f "$tmp" "$weights/chat-template.jinja"
  template_result=saved
}

# A path the list downloads: relative, plain, and it stays under the weights folder (no . or .. part).
plain_rel() {
  [[ "$1" =~ ^[A-Za-z0-9._+-][A-Za-z0-9._/+-]*$ ]] || return 1
  case "/$1/" in */../* | */./* | *//*) return 1 ;; esac
}

# read_sources FILE: fill src_model, src_repo, src_rev and src_path from `ygg models sources FILE`, each checked.
src_model=() src_repo=() src_rev=() src_path=()
read_sources() {
  local out m repo rev path extra
  out="$("$ygg" models sources "$1")" || exit 1
  while read -r m repo rev path extra; do
    [ -n "$m" ] || continue
    [ -n "$path" ] && [ -z "$extra" ] || die "ygg models sources $1 printed a line that is not <model> <repo> <revision> <path>: $m $repo $rev $path $extra"
    [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "model $m: the download repo '$repo' is not <owner>/<name>"
    [[ "$rev" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || die "model $m: the download revision '$rev' is not plain"
    plain_rel "$path" || die "model $m: the download file '$path' is not a plain path under the weights folder"
    src_model+=("$m") src_repo+=("$repo") src_rev+=("$rev") src_path+=("$path")
  done <<<"$out"
}

# setup: the whole first-time setup (the header says the steps); everything it refuses is checked before step 1.
do_setup() {
  local src tmpd="" abs p_in p_out p_cr extra v nv rc gpu_out preset line sec model tpl tpl_host="" tpl_make="" i missing=0 hf=()
  local -a models=()
  local -A tpls=()
  local num='^[0-9]+(\.[0-9]+)?$'
  if [ -e "$list" ]; then
    src="$list"
  else
    [ -n "$price" ] || bad "$list does not exist, and a new list needs --price IN:OUT[:CACHE_READ] (OpenRouter's price of the model, dollars per million tokens)"
    IFS=: read -r p_in p_out p_cr extra <<<"$price"
    [[ "$p_in" =~ $num ]] && [[ "$p_out" =~ $num ]] && { [ -z "$p_cr" ] || [[ "$p_cr" =~ $num ]]; } && [ -z "$extra" ] ||
      bad "--price '$price' is not IN:OUT or IN:OUT:CACHE_READ (numbers, dollars per million tokens)"
    case "$dir" in /*) abs="$dir" ;; *) abs="$PWD/$dir" ;; esac
    new_weights="${new_weights:-$abs/models/weights}" new_state="${new_state:-$abs/models/state}"
    for v in weights state; do
      nv="new_$v"
      [[ "${!nv}" =~ ^/[A-Za-z0-9._/@+-]*[A-Za-z0-9._@+-]$ ]] ||
        bad "--$v '${!nv}' is not an absolute path of letters, digits and . _ / @ + - only (ygg refuses others)"
    done
    [ -f "$example" ] || die "the example list $example is missing"
    for v in '^  weights: /abs/path/to/weights' '^  state: /abs/path/to/state' '^    price: '; do
      [ "$(grep -c -E -- "$v" "$example")" = 1 ] || die "the example list $example does not hold one line that matches '$v'"
    done
    tmpd="$(mktemp -d)"
    # shellcheck disable=SC2064 # the folder is known now
    trap "rm -rf -- '$tmpd'" EXIT
    src="$tmpd/models.yaml"
    {
      echo "# Written by scripts/ygg-models.sh setup from scripts/testdata/models/models.example.yaml."
      sed -E -e "s|^(  weights: )/abs/path/to/weights|\1$new_weights|" -e "s|^(  state: )/abs/path/to/state|\1$new_state|" \
        -e "s|^    price: .*|    price: {input: $p_in, output: $p_out${p_cr:+, cache_read: $p_cr}}   # OpenRouter's price, dollars per million tokens (setup --price)|" \
        "$example"
    } >"$src"
  fi
  # ygg reads the list (a new one too, before it is written): the server, the folders under sandbox.mounts.
  read_server "$src"
  check_names
  preset="$("$ygg" models preset "$src")" || exit 1
  sec=""
  while IFS= read -r line; do
    case "$line" in
      "["*"]") sec="${line#[}"; sec="${sec%]}"; models+=("$sec") ;;
      "chat-template-file = "*) [ -z "$sec" ] || tpls[$sec]="${line#chat-template-file = }" ;;
    esac
  done <<<"$preset"
  [ "${#models[@]}" -gt 0 ] || die "the list $list has no model"
  if [ -n "$want_model" ]; then
    model=""
    for v in "${models[@]}"; do [ "$v" != "$want_model" ] || model="$v"; done
    [ -n "$model" ] || bad "--model $want_model is not in the list (it has: ${models[*]})"
  else
    model="$(printf '%s\n' "${models[@]}" | LC_ALL=C sort | head -n 1)"
  fi
  tpl="${tpls[$model]:-}"
  case "$tpl" in
    "") ;;
    /models/*)
      plain_rel "${tpl#/models/}" || die "model $model: chat-template-file $tpl is not a plain path under /models"
      tpl_host="$weights/${tpl#/models/}"
      if [ ! -e "$tpl_host" ]; then
        [ "$tpl" = /models/chat-template.jinja ] ||
          die "model $model: chat-template-file $tpl is missing ($tpl_host); setup makes only /models/chat-template.jinja: put the file there, or name that one in $list"
        tpl_make=1
      fi ;;
  esac
  read_sources "$src"
  for i in "${!src_path[@]}"; do [ -e "$weights/${src_path[$i]}" ] || missing=1; done
  if [ "$missing" = 1 ]; then
    if command -v hf >/dev/null 2>&1; then hf=(hf)
    elif command -v uvx >/dev/null 2>&1; then hf=(uvx --from huggingface_hub hf)
    else die "a file of the list is missing, and neither hf nor uvx is on PATH to download it: install one (uv: https://docs.astral.sh/uv/; hf: pip install -U huggingface_hub)"
    fi
  fi

  # 1. The GPU.
  rc=0
  gpu_out="$("$gpu_sh" check --folder "$dir" 2>&1)" || rc=$?
  case "$rc" in
    0) gpu_out="$(printf '%s\n' "$gpu_out" | tail -n 1)"; echo "gpu: already in place (${gpu_out#gpu: })" ;;
    3)
      printf '%s\n' "$gpu_out"
      "$gpu_sh" setup --folder "$dir" || die "scripts/ygg-gpu.sh setup failed"
      echo "gpu: set up" ;;
    *) printf '%s\n' "$gpu_out" >&2; exit "$rc" ;;
  esac
  # 2. The list, and its folders.
  if [ -n "$tmpd" ]; then
    mkdir -p "$(dirname "$list")"
    v="$(mktemp "$(dirname "$list")/.models.yaml.XXXXXX")"
    cat "$src" >"$v"
    mv -f "$v" "$list"
    mkdir -p "$weights" "$state"
    echo "model list: written $list (weights $weights, state $state)"
  else
    [ -z "$new_weights$new_state$price" ] ||
      echo "ygg-models: $list exists: --weights, --state and --price count only for a new list, so it is used as is"
    mkdir -p "$weights"
    echo "model list: already in place ($list)"
  fi
  # 3. The downloads: a file that is there is never touched.
  [ "${#src_path[@]}" -gt 0 ] || echo "download: none in the list"
  for i in "${!src_path[@]}"; do
    if [ -e "$weights/${src_path[$i]}" ]; then echo "download: ${src_path[$i]}: already in place"; continue; fi
    "${hf[@]}" download "${src_repo[$i]}" "${src_path[$i]}" --revision "${src_rev[$i]}" --local-dir "$weights" ||
      die "the download of ${src_path[$i]} from ${src_repo[$i]} failed"
    [ -f "$weights/${src_path[$i]}" ] || die "the download of ${src_path[$i]} from ${src_repo[$i]} left no file at $weights/${src_path[$i]}"
    echo "download: ${src_path[$i]}: done"
  done
  # 4. The image.
  v="$("$ygg" models image)" || exit 1
  if exists image "$v"; then echo "image: already in place ($v)"; else build_image "$v"; echo "image: built $v"; fi
  # 5. Start and load. A server that runs while the template is missing cannot load the model: it starts again
  # without that line first.
  if [ -n "$tpl_make" ]; then
    do_stop
    [ "$stop_result" = absent ] || echo "server: stopped, to start without the missing chat template"
  fi
  do_start skip "$tpl_make"
  if [ "$start_result" = running ]; then
    echo "server: already running on $url"
    [ "$(cat "$state/preset.ini" 2>/dev/null)" = "$preset" ] ||
      echo "ygg-models: the server runs an older preset than the list's; to apply it: scripts/ygg-models.sh stop && scripts/ygg-models.sh start"
  elif [ -n "$tpl_make" ]; then
    echo "server: started on $url, without the chat template for now"
  else
    echo "server: started on $url"
  fi
  do_load "$model"
  if [ "$load_result" = already ]; then echo "load: $model: already loaded"; else echo "load: $model: loaded"; fi
  # 6. The template.
  if [ -z "$tpl" ]; then
    echo "template: none in the list for $model"
  elif [ -z "$tpl_host" ]; then
    echo "template: the list names $tpl, which is not under /models; setup leaves it as it is"
  elif [ -z "$tpl_make" ]; then
    echo "template: already in place ($tpl_host)"
  else
    do_template "$model" keep
    echo "template: saved $tpl_host"
    do_stop
    do_start skip
    echo "server: started again on $url, with the chat template"
    do_load "$model"
    if [ "$load_result" = already ]; then echo "load: $model: already loaded"; else echo "load: $model: loaded"; fi
  fi
}

# clean: the container, the network and the image; with --state and --weights, those files too.
do_clean() {
  local others tag f n i
  read_server "$list"
  check_names
  # Decide first: a refusal changes nothing.
  [ -z "$clean_weights" ] || read_sources "$list"
  if exists network "$network"; then
    others="$(pm container ls -a --filter "network=$network" --format '{{.Names}}')" || exit 2
    others="$(printf '%s\n' "$others" | grep -v -x -F -e "$name" -e '' || true)"
    [ -z "$others" ] ||
      die "other containers are on the network $network, so nothing was removed (the server, the network and the image stay): $(printf '%s\n' "$others" | tr '\n' ' ')- let their runs end, then run clean again"
  fi
  do_stop
  if [ "$stop_result" = absent ]; then echo "container $name: not there"; else echo "container $name: removed"; fi
  if exists network "$network"; then
    pm network rm "$network" >/dev/null
    echo "network $network: removed"
  else
    echo "network $network: not there"
  fi
  tag="$("$ygg" models image)" || exit 1
  if exists image "$tag"; then
    pm image rm "$tag" >/dev/null
    echo "image $tag: removed"
  else
    echo "image $tag: not there"
  fi
  if [ -n "$clean_state" ]; then
    n=0
    for f in "$state/preset.ini" "$state/preset.ini.tmp" "$state/allowed" "$state"/.allowed-*; do
      if [ -f "$f" ] || [ -L "$f" ]; then rm -f -- "$f"; n=$((n + 1)); fi
    done
    echo "state: removed $n files from $state (the folder stays)"
  fi
  if [ -n "$clean_weights" ]; then
    [ "${#src_path[@]}" -gt 0 ] || echo "weights: the list downloads no file; nothing deleted"
    for i in "${!src_path[@]}"; do
      f="$weights/${src_path[$i]}"
      if [ -d "$f" ] && [ ! -L "$f" ]; then echo "weights: $f is a folder; left as it is"
      elif [ -f "$f" ] || [ -L "$f" ]; then rm -f -- "$f"; echo "deleted $f"
      else echo "weights: ${src_path[$i]}: not there"
      fi
    done
    # hf download keeps its own state under the folder it downloads to: that exact folder, never another.
    f="${weights:?}/.cache/huggingface"
    if [ -d "$f" ] && [ ! -L "$f" ]; then rm -rf -- "$f"; echo "deleted $f (hf download's state)"; fi
  fi
}

case "$cmd" in
  setup) do_setup; exit 0 ;;
  clean) do_clean; exit 0 ;;
esac
read_server "$list"

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
    do_stop
    if [ "$stop_result" = absent ]; then echo "not running"; else echo "stopped $name"; fi
    ;;
  template)
    do_template "$1"
    if [ "$template_result" = already ]; then
      echo "model $1: the fix is already in place (the server's template has the system turn); nothing saved"
    else
      echo "saved $weights/chat-template.jinja; the list's chat-template-file: /models/chat-template.jinja uses it from the next start:"
      echo "  scripts/ygg-models.sh stop && scripts/ygg-models.sh start"
    fi
    ;;
  load)
    do_load "$1"
    echo "loaded $1"
    ;;
  start)
    do_start
    if [ "$start_result" = running ]; then
      echo "already running on $url (stop first to apply list changes: scripts/ygg-models.sh stop)"
    else
      echo "ready on $url (container $name; log: podman logs $name)"
    fi
    ;;
esac

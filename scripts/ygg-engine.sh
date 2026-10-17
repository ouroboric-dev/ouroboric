#!/usr/bin/env bash
# The container engine environment of the factory's real-engine runs, in one place, so that a run never
# depends on what the shell happens to have set (a root socket in CONTAINER_HOST, a registry credential
# helper that waits for cloud credentials, the wrong devcontainer CLI).
#   ygg-engine.sh check [--folder DIR]      check the engine and print one line per check; exit 2 on the first problem
#   ygg-engine.sh env   [--folder DIR]      check, then print `export` lines to eval:  eval "$(ygg-engine.sh env)"
#   ygg-engine.sh run   [--folder DIR] -- CMD...   check, then run CMD in that environment
# DIR (default $HOME/ygg-it) holds factory.yaml; its `sandbox.engine` is the one place that names the engine
# (a unix:// URL of a rootless socket). The environment it sets:
#   CONTAINER_HOST      the engine of factory.yaml (an ambient value, e.g. the root socket, is replaced);
#                       CONTAINER_CONNECTION and DOCKER_HOST are unset
#   DOCKER_CONFIG       DIR/empty-docker, whose config.json is {}: no credential helper can be called
#   REGISTRY_AUTH_FILE  DIR/empty-auth.json, which is {}
#   PATH                DIR/dc/node_modules/.bin first (the devcontainer CLI)
# The checks: the socket exists; the engine answers within YGG_ENGINE_TIMEOUT seconds (20) and is rootless;
# the devcontainer CLI is YGG_CLI_VERSION (0.89.0); the bind mount YGG_BIND (/mnt/wsl/ygg-bind) is there.
# It never starts, stops or restarts the engine: if it hangs, ask before restarting it.
set -euo pipefail
usage() { echo "usage: ygg-engine.sh check|env|run [--folder DIR] [-- CMD...]" >&2; exit 2; }
[ $# -ge 1 ] || usage
mode="$1"; shift
dir="$HOME/ygg-it"
while [ $# -gt 0 ]; do
  case "$1" in
    --folder) dir="${2:?--folder needs a folder}"; shift 2 ;;
    --) shift; break ;;
    *) usage ;;
  esac
done
case "$mode" in check | env) [ $# -eq 0 ] || usage ;; run) [ $# -gt 0 ] || usage ;; *) usage ;; esac
fail() { echo "ygg-engine: $*" >&2; exit 2; }

[ -f "$dir/factory.yaml" ] || fail "$dir/factory.yaml is missing; it names the engine (sandbox.engine)"
engine="$(sed -n 's/^[[:space:]]*engine:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$dir/factory.yaml" | head -n 1)"
case "$engine" in unix://*) ;; *) fail "sandbox.engine in $dir/factory.yaml is '${engine:-missing}'; it must be a unix:// URL" ;; esac
sock="${engine#unix://}"
want="${YGG_CLI_VERSION:-0.89.0}" bind="${YGG_BIND:-/mnt/wsl/ygg-bind}" wait="${YGG_ENGINE_TIMEOUT:-20}"

mkdir -p "$dir/empty-docker"
[ -f "$dir/empty-docker/config.json" ] || printf '{}\n' > "$dir/empty-docker/config.json"
[ -f "$dir/empty-auth.json" ] || printf '{}\n' > "$dir/empty-auth.json"
export CONTAINER_HOST="$engine" DOCKER_CONFIG="$dir/empty-docker" REGISTRY_AUTH_FILE="$dir/empty-auth.json"
unset CONTAINER_CONNECTION DOCKER_HOST
export PATH="$dir/dc/node_modules/.bin:$PATH"

[ -S "$sock" ] || fail "the engine socket $sock is not there; is the Podman machine running?"
if ! rootless="$(timeout "$wait" podman --url "$engine" info --format '{{.Host.Security.Rootless}}' 2>/dev/null)"; then
  fail "the engine at $engine did not answer in ${wait}s; the machine may be hung (a registry credential helper can wait for cloud credentials). Ask before restarting it"
fi
[ "$rootless" = true ] || fail "the engine at $engine is not rootless ($rootless); the factory runs on the user socket only, never the root one"
got="$(devcontainer --version 2>/dev/null | head -n 1 || true)"
[ "$got" = "$want" ] || fail "the devcontainer CLI is '${got:-missing}', want $want; install it in $dir/dc (npm install --prefix $dir/dc @devcontainers/cli@$want)"
[ -d "$bind" ] || fail "the bind mount $bind is missing; a WSL restart removes it"

case "$mode" in
  check)
    echo "ygg-engine: engine $engine answers and is rootless"
    echo "ygg-engine: devcontainer CLI $got"
    echo "ygg-engine: bind mount $bind is there"
    echo "ygg-engine: DOCKER_CONFIG and REGISTRY_AUTH_FILE are empty ($dir)" ;;
  env)
    printf 'export CONTAINER_HOST=%q DOCKER_CONFIG=%q REGISTRY_AUTH_FILE=%q PATH=%q\nunset CONTAINER_CONNECTION DOCKER_HOST\n' \
      "$CONTAINER_HOST" "$DOCKER_CONFIG" "$REGISTRY_AUTH_FILE" "$PATH" ;;
  run) exec "$@" ;;
esac

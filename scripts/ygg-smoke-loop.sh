#!/usr/bin/env bash
# Run the loop smoke realm (v0-H11) with its checks, then print the evidence report.
#   ygg-smoke-loop.sh [--build] [--folder DIR] [--env FILE] [--realm DIR] [--clip]
# Needs: DIR/factory.yaml (the operator's config; this script never writes it), the devcontainer CLI 0.89.0
# first on PATH (or in DIR/dc/node_modules/.bin), the engine up and the bind mount present. It
#   1. checks the devcontainer CLI version and the bind mount, and stops with a reason if one is wrong;
#   2. makes the project DIR/smoke-loop if it is missing (never touches an existing one: the state that an
#      earlier run left in it is normal, and ygg itself refuses a run it cannot start);
#   3. loads the credentials from FILE in a subshell, without printing them;
#   4. with --build, builds the sandbox images;
#   5. runs the realm and keeps its raw output in DIR/h11-run.txt (shown live as ygg prints it: do not paste
#      that file, paste the report);
#   6. prints the report of ygg-evidence.sh, with the credentials removed (also in DIR/h11-report.txt): paste it.
# Defaults: DIR=$HOME/ygg-it, FILE=$HOME/.config/ouroboric/factory.env, realm=testdata/smoke-loop of the
# odin folder. For tests and other machines: YGG_CMD (how ygg runs), YGG_ODIN (the odin folder),
# YGG_BIND (the bind mount, default /mnt/wsl/ygg-bind) and YGG_CLI_VERSION (default 0.89.0).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="$HOME/ygg-it" envfile="$HOME/.config/ouroboric/factory.env" realm='' build=0 clip=()
while [ $# -gt 0 ]; do
  case "$1" in
    --build) build=1; shift ;;
    --folder) dir="${2:?--folder needs a folder}"; shift 2 ;;
    --env) envfile="${2:?--env needs a file}"; shift 2 ;;
    --realm) realm="${2:?--realm needs a folder}"; shift 2 ;;
    --clip) clip=(--clip); shift ;;
    *) echo "usage: ygg-smoke-loop.sh [--build] [--folder DIR] [--env FILE] [--realm DIR] [--clip]" >&2; exit 2 ;;
  esac
done
odin="${YGG_ODIN:-$HERE/../../yggdrasil/odin}"
[ -n "$realm" ] || realm="$odin/testdata/smoke-loop"
want="${YGG_CLI_VERSION:-0.89.0}" bind="${YGG_BIND:-/mnt/wsl/ygg-bind}"
export PATH="$dir/dc/node_modules/.bin:$PATH"
[ -f "$dir/factory.yaml" ] || { echo "smoke-loop: $dir/factory.yaml is missing; copy odin/testdata/smoke-loop/factory.example.yaml there and set the mount" >&2; exit 2; }
[ -f "$envfile" ] || { echo "smoke-loop: the credentials file $envfile is missing" >&2; exit 2; }
got="$(devcontainer --version 2>/dev/null | head -n 1 || true)"
[ "$got" = "$want" ] || { echo "smoke-loop: devcontainer CLI is '${got:-missing}', want $want; put the right one first on PATH" >&2; exit 2; }
[ -d "$bind" ] || { echo "smoke-loop: the bind mount $bind is missing; a WSL restart removes it (see Phase 3 v0-H07)" >&2; exit 2; }

project="$dir/smoke-loop"
if [ ! -d "$project" ]; then
  mkdir -p "$project"
  git -C "$project" init -q -b main
  printf 'root: true\nowner: ouroboric-dev\nvisibility: private\n' > "$project/umbrella.yaml"
  git -C "$project" add umbrella.yaml
  git -C "$project" -c user.name=ygg -c user.email=ygg@example.invalid commit -q -m "the smoke loop project"
  echo "smoke-loop: made $project"
fi

ygg="${YGG_CMD:-}"
if [ -z "$ygg" ]; then
  if command -v ygg >/dev/null 2>&1; then ygg=ygg; else ygg="cd '$odin' && go run ./cmd/ygg"; fi
fi
out="$dir/h11-run.txt"
# The credentials live only in this subshell; nothing here prints them.
set +e
(
  set -a
  # shellcheck source=/dev/null
  . "$envfile"
  set +a
  if [ "$build" -eq 1 ]; then eval "$ygg sandbox build --config '$dir/factory.yaml' --realm '$realm'"; fi
  eval "$ygg run --project '$project' --config '$dir/factory.yaml' --realm '$realm'"
) 2>&1 | tee "$out"
rc="${PIPESTATUS[0]}"
set -e
echo "smoke-loop: the run ended with exit code $rc (0 done, 1 a node failed, 3 stopped, 4 paused)" >&2

report="$dir/h11-report.txt"
# The report is made with the credentials in its environment, so that it can remove their exact values.
( set -a
  # shellcheck source=/dev/null
  . "$envfile"
  set +a
  YGG_CMD="$ygg" "$HERE/ygg-evidence.sh" --config "$dir/factory.yaml" --output "$out" ${clip[@]+"${clip[@]}"} "$project"
) | tee "$report"
echo "smoke-loop: the report is in $report" >&2
exit "$rc"

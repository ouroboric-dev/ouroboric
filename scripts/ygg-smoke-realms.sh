#!/usr/bin/env bash
# Run the realms smoke run (v0-H13) with real agents, then print the evidence report.
#   ygg-smoke-realms.sh [--build] [--folder DIR] [--env FILE] [--clip] [--graph NAME|DIR] [--brief FILE] [--tag TAG]
# The run builds a tiny product from two realm leaves (smoke-lead and smoke-api, in odin/testdata/smoke-realms):
# real planners write the leaves file and the plan in scratch workspaces in sandboxes, Odin publishes them,
# creates the leaves from their realms' templates, and a real implementer builds one task in each leaf.
# Needs: DIR/factory.yaml (the operator's config, copied from odin/testdata/smoke-realms/factory.example.yaml
# with its engine, mounts and realms.dir set; this script never writes it), the devcontainer CLI 0.89.0 first
# on PATH (or in DIR/dc/node_modules/.bin), the engine up and the bind mount present. It
#   1. checks the devcontainer CLI version and the bind mount, and stops with a reason if one is wrong;
#   2. makes a new project DIR/smoke-realms-<time> (an umbrella with no leaves: the run decides its leaves);
#   3. loads the credentials from FILE in a subshell, without printing them;
#   4. with --build, builds the sandbox images of every realm in the realm folder;
#   5. runs the realm and keeps its raw output in DIR/h13-run.txt (shown live as ygg prints it: do not paste
#      that file, paste the report);
#   6. prints the report of ygg-evidence.sh, with the credentials removed (also in DIR/h13-report.txt): paste it.
# The same script runs the content smoke run (v0-H15) with --graph software --brief BRIEF --tag h15: the real
# realms, scripted agents, the real check ladder. --graph is the graph pack, a name or a folder (default: the
# smoke-lead folder of odin/testdata/smoke-realms; a name needs a graphs section in factory.yaml), --brief the
# brief the run is given, and --tag names the files of the run and its report in DIR (h13 by default).
# Defaults: DIR=$HOME/ygg-it, FILE=$HOME/.config/ouroboric/factory.env. For tests and other machines: YGG_CMD
# (how ygg runs), YGG_ODIN (the odin folder), YGG_BIND (the bind mount, default /mnt/wsl/ygg-bind) and
# YGG_CLI_VERSION (default 0.89.0). The engine environment comes from ygg-engine.sh (YGG_ENGINE_CHECK=0 skips it).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="$HOME/ygg-it" envfile="$HOME/.config/ouroboric/factory.env" build=0 clip=() graph="" brief="" tag=h13
while [ $# -gt 0 ]; do
  case "$1" in
    --build) build=1; shift ;;
    --folder) dir="${2:?--folder needs a folder}"; shift 2 ;;
    --env) envfile="${2:?--env needs a file}"; shift 2 ;;
    --clip) clip=(--clip); shift ;;
    --graph) graph="${2:?--graph needs a name or a folder}"; shift 2 ;;
    --brief) brief="${2:?--brief needs a file}"; shift 2 ;;
    --tag) tag="${2:?--tag needs a name}"; shift 2 ;;
    *) echo "usage: ygg-smoke-realms.sh [--build] [--folder DIR] [--env FILE] [--clip] [--graph NAME|DIR] [--brief FILE] [--tag TAG]" >&2; exit 2 ;;
  esac
done
odin="${YGG_ODIN:-$HERE/../../yggdrasil/odin}"
[ -n "$graph" ] || graph="$odin/testdata/smoke-realms/smoke-lead"
want="${YGG_CLI_VERSION:-0.89.0}" bind="${YGG_BIND:-/mnt/wsl/ygg-bind}"
export PATH="$dir/dc/node_modules/.bin:$PATH"
# The engine environment is ygg-engine.sh's: the engine of DIR/factory.yaml (never the shell's CONTAINER_HOST),
# an empty registry config, and a check that the engine answers and is rootless. YGG_ENGINE_CHECK=0 skips it (tests).
if [ "${YGG_ENGINE_CHECK:-1}" = 1 ]; then
  engine_env="$("$HERE/ygg-engine.sh" env --folder "$dir")" || exit 2
  eval "$engine_env"
fi
[ -f "$dir/factory.yaml" ] || { echo "smoke-realms: $dir/factory.yaml is missing; copy odin/testdata/smoke-realms/factory.example.yaml there and set the engine, the mount and realms.dir" >&2; exit 2; }
[ -f "$envfile" ] || { echo "smoke-realms: the credentials file $envfile is missing" >&2; exit 2; }
grep -q '^realms:' "$dir/factory.yaml" || { echo "smoke-realms: $dir/factory.yaml has no realms section: realms.dir says where the leaf realms are" >&2; exit 2; }
case "$graph" in */*) ;; *) grep -q '^graphs:' "$dir/factory.yaml" || { echo "smoke-realms: $dir/factory.yaml has no graphs section: the run is given a graph by name ($graph), and graphs.dir says where it is" >&2; exit 2; } ;; esac
[ -z "$brief" ] || [ -f "$brief" ] || { echo "smoke-realms: the brief $brief is missing" >&2; exit 2; }
got="$(devcontainer --version 2>/dev/null | head -n 1 || true)"
[ "$got" = "$want" ] || { echo "smoke-realms: devcontainer CLI is '${got:-missing}', want $want; put the right one first on PATH" >&2; exit 2; }
[ -d "$bind" ] || { echo "smoke-realms: the bind mount $bind is missing; a WSL restart removes it (see Phase 3 v0-H07)" >&2; exit 2; }
mountpoint -q "$bind" || { echo "smoke-realms: the bind mount $bind is a folder with nothing mounted on it; run: sudo mount --bind <the host folder of factory.yaml's mount> $bind (a WSL restart removes it, see Phase 3 v0-H07)" >&2; exit 2; }

project="$dir/smoke-realms-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$project"
git -C "$project" init -q -b main
printf 'root: true\nowner: ouroboric-dev\nvisibility: private\n' > "$project/umbrella.yaml"
git -C "$project" add umbrella.yaml
git -C "$project" -c user.name=ygg -c user.email=ygg@example.invalid commit -q -m "the realms smoke project"
echo "smoke-realms: made $project"

ygg="${YGG_CMD:-}"
if [ -z "$ygg" ]; then
  if command -v ygg >/dev/null 2>&1; then ygg=ygg; else ygg="cd '$odin' && go run ./cmd/ygg"; fi
fi
out="$dir/$tag-run.txt"
# The credentials live only in this subshell; nothing here prints them.
set +e
(
  set -a
  # shellcheck source=/dev/null
  . "$envfile"
  set +a
  if [ "$build" -eq 1 ]; then eval "$ygg sandbox build --config '$dir/factory.yaml' --all"; fi
  eval "$ygg run --project '$project' --config '$dir/factory.yaml' --graph '$graph' ${brief:+--brief '$brief'}"
) 2>&1 | tee "$out"
rc="${PIPESTATUS[0]}"
set -e
echo "smoke-realms: the run ended with exit code $rc (0 done, 1 a node failed, 3 stopped, 4 paused, 5 done with tasks given up)" >&2

report="$dir/$tag-report.txt"
# The report is made with the credentials in its environment, so that it can remove their exact values.
( set -a
  # shellcheck source=/dev/null
  . "$envfile"
  set +a
  YGG_CMD="$ygg" "$HERE/ygg-evidence.sh" --config "$dir/factory.yaml" --output "$out" ${clip[@]+"${clip[@]}"} "$project"
) | tee "$report"
echo "smoke-realms: the report is in $report" >&2
exit "$rc"

#!/usr/bin/env bash
# Shared helpers for the plan-* scripts. Source this file; do not run it.
#
# An SDD workspace is <root>/.superpowers/sdd/<slug>/, made by superpowers' sdd-workspace for one plan.
# Its plan-path file names the plan, relative to <root> or absolute. The root holds the plan and the
# component repos, each in a folder of its own (for Yggdrasil: the umbrella with its submodules).

# plan_load WORKSPACE: set PLAN_WS (the workspace), PLAN_ROOT (the root) and PLAN_FILE (the plan).
plan_load() {
  local ws="${1:-}" p
  if [ ! -f "$ws/plan-path" ]; then
    echo "$ws is not an SDD workspace: it has no plan-path file" >&2
    return 2
  fi
  PLAN_WS="$(cd "$ws" && pwd -P)"
  PLAN_ROOT="$(cd "$PLAN_WS/../../.." && pwd -P)"
  p="$(cat "$PLAN_WS/plan-path")"
  case "$p" in /*) PLAN_FILE="$p" ;; *) PLAN_FILE="$PLAN_ROOT/$p" ;; esac
  if [ ! -f "$PLAN_FILE" ]; then
    echo "the plan $PLAN_FILE, named by $PLAN_WS/plan-path, does not exist" >&2
    return 2
  fi
}

# plan_gowork DIR: write DIR/go.work that uses every folder of DIR (links included) that holds a go.mod,
# with the Go version of the first one. Plan reference workspaces build their repos side by side.
plan_gowork() {
  local dir="$1" gomod name gover=''
  local -a mods=()
  for gomod in "$dir"/*/go.mod; do
    [ -e "$gomod" ] || continue
    name="$(basename "$(dirname "$gomod")")"
    mods+=("$name")
    [ -n "$gover" ] || gover="$(awk '$1 == "go" { print $2; exit }' "$gomod")"
  done
  {
    printf 'go %s\n\nuse (\n' "${gover:-1.21}"
    for name in "${mods[@]}"; do printf '\t./%s\n' "$name"; done
    printf ')\n'
  } > "$dir/go.work"
}

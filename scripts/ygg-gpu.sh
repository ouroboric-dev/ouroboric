#!/usr/bin/env bash
# The GPU of the factory's engine, set up once and checked again after a driver update or on a new machine, so no
# step is done by hand twice. The engine resolves a CDI device, so the NVIDIA container toolkit and the CDI spec
# (/etc/cdi/nvidia.yaml) must be where the engine runs: on a rootless Podman machine under WSL2, in the machine's
# own WSL distro (Fedora, PID 1 is WSL's init, no systemd, so the toolkit's refresh units never run).
#   ygg-gpu.sh setup [--machine NAME] [--folder DIR]   install the toolkit (pinned) where it is missing, generate
#                                                      the CDI spec where it is missing or stale, then run check
#   ygg-gpu.sh check [--machine NAME] [--folder DIR]   run a CUDA container through ygg-engine.sh and print
#                                                      `gpu: <name> <memory>`
# NAME defaults to the machine `podman machine inspect` names as the default one (else the one the engine socket
# of DIR/factory.yaml names, .../podman-sockets/NAME/...: a Linux podman cannot list the Windows side's machines); its distro is podman-NAME (NAME
# itself when it starts with podman-). DIR is passed to ygg-engine.sh (its default is $HOME/ygg-it).
# Exit codes: 0 ready; 1 setup or the container failed, or the engine is not a Podman machine on WSL2 (setup
# changes nothing then); 2 the engine does not answer, or bad usage; 3 not ready: `missing: toolkit`, `missing: spec`
# or `missing: stale spec`, with the command that fixes it (a stale spec is one that names no folder, or a
# /usr/lib/wsl/drivers/<folder> that no longer exists).
# The engine is checked first (before any wsl.exe -d, which boots a stopped distro), by setup too. The state is read by
# one constant probe script in the distro; a wsl.exe that fails or says nothing is exit 2, not a missing state.
# Root commands in the distro run as `wsl.exe -d <distro> -u root -- sh -s` (the script on stdin): no sudo. It never starts, stops,
# restarts or re-creates the engine or the machine, and sets no engine variable (ygg-engine.sh does).
# Pinned: the toolkit YGG_GPU_TOOLKIT (1.20.1) and the CUDA image YGG_GPU_IMAGE (by digest).
# Tests: YGG_ENGINE_SH replaces the ygg-engine.sh that sits next to this script.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
engine_sh="${YGG_ENGINE_SH:-$HERE/ygg-engine.sh}"
ver="${YGG_GPU_TOOLKIT:-1.20.1}"
image="${YGG_GPU_IMAGE:-docker.io/nvidia/cuda@sha256:59436e8ac61921052d8f420be8b8cb8b117f1d7cc643397a289e37aaa0b83ea1}"
spec=/etc/cdi/nvidia.yaml
repo_url=https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo

usage() { echo "usage: ygg-gpu.sh setup|check [--machine NAME] [--folder DIR]" >&2; exit 2; }
[ $# -ge 1 ] || usage
mode="$1"; shift
case "$mode" in setup | check) ;; *) usage ;; esac
machine="" folder=() dir="$HOME/ygg-it"
while [ $# -gt 0 ]; do
  case "$1" in
    --machine) machine="${2:?--machine needs a name}"; shift 2 ;;
    --folder) dir="${2:?--folder needs a folder}"; folder=(--folder "$dir"); shift 2 ;;
    *) usage ;;
  esac
done

refuse() { echo "ygg-gpu: this is not a Podman machine on WSL2 ($1); nothing was changed" >&2; exit 1; }
if [ -z "$machine" ]; then
  machine="$(podman machine inspect --format '{{.Name}}' 2>/dev/null | head -n 1)" || true
  if [ -z "$machine" ]; then # a Linux podman cannot list the machines of the Windows side: the engine socket names it
    machine="$(sed -n 's|^[[:space:]]*engine:[[:space:]]*unix://.*/podman-sockets/\([^/]*\)/.*|\1|p' "$dir/factory.yaml" 2>/dev/null | head -n 1)" || true
  fi
  [ -n "$machine" ] || refuse "podman names no default machine"
fi
command -v wsl.exe >/dev/null 2>&1 || refuse "wsl.exe is not there"
case "$machine" in podman-*) distro="$machine" ;; *) distro="podman-$machine" ;; esac
distros="$(wsl.exe -l -q 2>/dev/null | tr -d '\0\r')" || true # wsl.exe prints UTF-16
printf '%s\n' "$distros" | grep -q -x -F -- "$distro" || refuse "WSL has no distro $distro for the machine $machine"

# The script goes on stdin: wsl.exe hands a command line to the distro's default shell, which expands $... first.
root() { printf '%s\n' "$1" | wsl.exe -d "$distro" -u root -- sh -s; }

# The engine must answer before any wsl.exe -d call: a wsl.exe -d boots a stopped distro, and a machine that is
# stopped is the engine's business, not this script's.
engine_up() {
  local err rc=0
  err="$(mktemp)"
  "$engine_sh" check "${folder[@]}" >/dev/null 2>"$err" || rc=$?
  if [ "$rc" -ne 0 ]; then cat "$err" >&2; rm -f -- "$err"; echo "ygg-gpu: the engine does not answer" >&2; exit 2; fi
  rm -f -- "$err"
}
engine_up

# state: set st to ok, toolkit, spec or "stale spec", from one probe script that runs in the distro. The script is a
# constant: nothing is interpolated into it. A wsl.exe that fails, or says nothing, is a transport problem (exit 2),
# never a missing state. A spec that names no /usr/lib/wsl/drivers/ folder cannot be current: it is stale.
# shellcheck disable=SC2016 # the probe runs in the distro: its $ must stay literal
probe='command -v nvidia-ctk >/dev/null 2>&1 || { echo toolkit; exit 0; }
[ -s /etc/cdi/nvidia.yaml ] || { echo spec; exit 0; }
dirs="$(grep -o "/usr/lib/wsl/drivers/[^/\"[:space:]]*" /etc/cdi/nvidia.yaml | sort -u)"
[ -n "$dirs" ] || { echo "stale spec"; exit 0; }
set -f
for d in $dirs; do
  [ -d "$d" ] || { echo "stale spec"; exit 0; }
done
echo ok'
st=""
state() {
  local out rc=0
  out="$(root "$probe" 2>/dev/null)" || rc=$?
  out="$(printf '%s\n' "$out" | tr -d '\r' | tail -n 1)"
  case "$rc:$out" in
    0:ok | 0:toolkit | 0:spec | "0:stale spec") st="$out" ;;
    *) echo "ygg-gpu: could not read the state of the GPU setup in $distro (wsl.exe exit $rc, answer '$out')" >&2; exit 2 ;;
  esac
}

do_check() {
  local out
  state
  if [ "$st" != ok ]; then
    echo "missing: $st"
    printf 'fix: %s setup --machine %q' "$0" "$machine"
    [ ${#folder[@]} -eq 0 ] || printf ' --folder %q' "$dir"
    echo
    exit 3
  fi
  out="$("$engine_sh" run "${folder[@]}" -- podman run --rm --device nvidia.com/gpu=all "$image" \
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>&1)" || {
    echo "ygg-gpu: the CUDA container failed (after a Windows driver update, run scripts/ygg-gpu.sh setup):" >&2; printf '%s\n' "$out" >&2; exit 1
  }
  echo "gpu: $(printf '%s\n' "$out" | tail -n 1 | sed 's/, / /')"
}

if [ "$mode" = setup ]; then
  state
  if [ "$st" = toolkit ]; then
    echo "ygg-gpu: installing the NVIDIA container toolkit $ver in $distro"
    v="$ver-1"
    root "curl -fsSL $repo_url -o /etc/yum.repos.d/nvidia-container-toolkit.repo && dnf install -y nvidia-container-toolkit-$v nvidia-container-toolkit-base-$v libnvidia-container-tools-$v libnvidia-container1-$v </dev/null" ||
      { echo "ygg-gpu: the toolkit install failed" >&2; exit 1; }
    st=spec
  fi
  if [ "$st" = spec ] || [ "$st" = "stale spec" ]; then
    echo "ygg-gpu: generating the CDI spec ($st) in $distro"
    root "mkdir -p /etc/cdi && nvidia-ctk cdi generate --output=$spec" >/dev/null ||
      { echo "ygg-gpu: nvidia-ctk cdi generate failed" >&2; exit 1; }
  fi
fi
do_check

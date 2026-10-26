#!/usr/bin/env bash
# Tests for ygg-gpu.sh.   scripts/tests/ygg-gpu.test.sh
# A fake `wsl.exe` (the machine's distro is a folder of state files), a fake `podman` (machine inspect) and a fake
# ygg-engine.sh (YGG_ENGINE_SH) stand in for the real tools; a fake `sudo` logs any call. The whole test runs under
# env -i (hermetic.sh): no real wsl.exe, podman or engine is ever called.
# shellcheck disable=SC2329 # check calls has and hasnt by name
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$HERE/hermetic.sh"
hermetic_enter "$@"
S="$HERE/.."
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
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
calls() { grep -c -F -- "$1" "$T/wsl.calls" 2>/dev/null || true; }

M="$T/m"            # the machine's distro: toolkit (file), spec (file), fs/ (driver store folders)
export FAKE_M="$M" FAKE_LOG="$T/wsl.calls"
cat >"$T/bin/wsl.exe" <<'FAKE'
#!/bin/bash
# wsl.exe -l -q | wsl.exe -d NAME -u root -- sh -s (script on stdin: runs unchanged)
# The real wsl.exe hands a command line to the distro's shell, which expands $... before sh runs: the `sh -c CMD` form
# loses every $name in CMD (as on the real machine). The fake does the same, for names.
if [ "$1" = "-l" ]; then printf 'Ubuntu\r\n%s\r\n' "$(cat "$FAKE_M/distro")" | sed 's/./&\x00/g'; exit 0; fi
[ "$1" = "-d" ] && [ "$3" = "-u" ] && [ "$4" = "root" ] && [ "$5" = "--" ] && [ "$6" = "sh" ] || { echo "fake wsl: bad args $*" >&2; exit 64; }
case "$7" in
  -s) [ $# -eq 7 ] || { echo "fake wsl: bad args $*" >&2; exit 64; }; cmd="$(cat)" ;;
  -c) cmd="$(printf '%s' "$8" | sed -E 's/\$[A-Za-z_][A-Za-z0-9_]*//g')" ;;
  *) echo "fake wsl: bad args $*" >&2; exit 64 ;;
esac
echo "$2: $cmd" >>"$FAKE_LOG"
case "$cmd" in
  *"echo toolkit"*) # the in-distro probe: run it for real against the fake distro's files
    [ -z "$FAKE_WSL_FAIL" ] || { echo "wsl: the distro does not start" >&2; exit 1; }
    [ -z "$FAKE_WSL_EMPTY" ] || exit 0
    probe="${cmd//\/etc\/cdi\/nvidia.yaml/$FAKE_M/spec}"
    probe="${probe//command -v nvidia-ctk >\/dev\/null 2>&1/test -e $FAKE_M/toolkit}"
    probe="${probe//\[ -d \"\$d\" \]/[ -d \"$FAKE_M/fs/\$(basename \"\$d\")\" ]}"
    exec sh -c "$probe" ;;
  *'echo "[stdin'* | *'echo "[cmdline'*) exec sh -c "$cmd" ;;
  *"dnf install"*) touch "$FAKE_M/toolkit"; exit 0 ;;
  *"cdi generate"*) { echo "devices:"; for d in "$FAKE_M"/fs/*; do echo "  path: /usr/lib/wsl/drivers/$(basename "$d")/x.so"; done; } >"$FAKE_M/spec"; exit 0 ;;
  "command -v nvidia-ctk"*) [ -e "$FAKE_M/toolkit" ]; exit $? ;;
  "cat /etc/cdi/nvidia.yaml"*) cat "$FAKE_M/spec"; exit $? ;;
  "test -d "*) [ -d "$FAKE_M/fs/$(basename "${cmd#test -d }")" ]; exit $? ;;
esac
echo "fake wsl: unexpected command $cmd" >&2; exit 65
FAKE
cat >"$T/bin/podman" <<'FAKE'
#!/bin/sh
echo "podman $*" >>"$FAKE_LOG.podman"
[ "$1 $2" = "machine inspect" ] || exit 97
[ -z "$FAKE_NOMACHINE" ] || { echo "Error: no machine" >&2; exit 125; }
echo "podman-machine-default"
FAKE
cat >"$T/bin/sudo" <<'FAKE'
#!/bin/sh
echo "sudo $*" >>"$FAKE_LOG.sudo"; exit 1
FAKE
cat >"$T/engine.sh" <<'FAKE'
#!/bin/bash
echo "engine $*" >>"$FAKE_LOG.engine"
[ -z "$FAKE_ENGINE_DOWN" ] || { echo "ygg-engine: the engine socket is not there" >&2; exit 2; }
if [ "$1" = check ]; then exit 0; fi
[ "$1" = run ] || exit 64
echo "NVIDIA GeForce RTX 4090, 24564 MiB"
FAKE
chmod +x "$T/bin/"* "$T/engine.sh"
export YGG_ENGINE_SH="$T/engine.sh"

reset() { # have-toolkit|no-toolkit  none|current|stale
  rm -rf "$M" "$FAKE_LOG" "$FAKE_LOG".*; mkdir -p "$M/fs/drv_a" "$M/fs/drv_b"; : >"$FAKE_LOG"
  echo podman-machine-default >"$M/distro"
  [ "$1" = have-toolkit ] && touch "$M/toolkit"
  case "$2" in
    current) printf 'devices:\n  path: /usr/lib/wsl/drivers/drv_a/x.so\n  path: /usr/lib/wsl/drivers/drv_b/y.so\n' >"$M/spec" ;;
    stale) printf 'devices:\n  path: /usr/lib/wsl/drivers/drv_a/x.so\n  path: /usr/lib/wsl/drivers/gone_c/y.so\n' >"$M/spec" ;;
  esac
  return 0
}
engine_ran() { [ -s "$FAKE_LOG.engine" ] && grep -q -F 'nvidia-smi' "$FAKE_LOG.engine"; }

# --- check
reset have-toolkit current
run "$S/ygg-gpu.sh" check
check "check with everything in place prints the GPU and exits 0" bash -c "[ $rc = 0 ] && grep -q -F 'gpu: NVIDIA GeForce RTX 4090 24564 MiB' '$T/out'"
check "it ran the CUDA image pinned by digest through ygg-engine" grep -q -F 'docker.io/nvidia/cuda@sha256:59436e8ac61921052d8f420be8b8cb8b117f1d7cc643397a289e37aaa0b83ea1' "$FAKE_LOG.engine"
check "with the CDI device" grep -q -F -- '--device nvidia.com/gpu=all' "$FAKE_LOG.engine"
check "and asked nvidia-smi for the name and memory" grep -q -F -- 'nvidia-smi --query-gpu=name,memory.total --format=csv,noheader' "$FAKE_LOG.engine"
check "and it found the default machine with podman machine inspect" grep -q -F 'machine inspect' "$FAKE_LOG.podman"

reset no-toolkit none
run "$S/ygg-gpu.sh" check
check "check without the toolkit exits 3 and says missing: toolkit" bash -c "[ $rc = 3 ]" 
check "and names the command that fixes it" has "ygg-gpu.sh setup"
check "and says missing: toolkit" has "missing: toolkit"
check "and does not run the container" bash -c "! grep -q nvidia-smi '$FAKE_LOG.engine'"

reset have-toolkit none
run "$S/ygg-gpu.sh" check
check "check with the toolkit and no spec exits 3: missing: spec" bash -c "[ $rc = 3 ] && grep -q -F 'missing: spec' '$T/out' && ! grep -q 'stale' '$T/out'"

reset have-toolkit stale
run "$S/ygg-gpu.sh" check
check "check with a spec naming a gone driver folder exits 3: missing: stale spec" bash -c "[ $rc = 3 ] && grep -q -F 'missing: stale spec' '$T/out'"
check "and names setup" has "ygg-gpu.sh setup"

reset have-toolkit current
FAKE_ENGINE_DOWN=1 run "$S/ygg-gpu.sh" check
check "check exits 2 when the engine does not answer" bash -c "[ $rc = 2 ] && grep -q 'engine socket' '$T/out'"

# --- setup
reset no-toolkit none
run "$S/ygg-gpu.sh" setup
check "setup on an empty machine installs the pinned toolkit, generates the spec and runs check" bash -c "[ $rc = 0 ] && grep -q -F 'gpu: NVIDIA GeForce RTX 4090' '$T/out'"
check "the install is pinned to 1.20.1 and from NVIDIA's rpm repo" bash -c "grep -F 'dnf install' '$FAKE_LOG' | grep -q -F '1.20.1' && grep -q -F 'nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo' '$FAKE_LOG'"
check "the spec is generated once into /etc/cdi/nvidia.yaml" bash -c "[ \"\$(grep -c -F 'cdi generate --output=/etc/cdi/nvidia.yaml' '$FAKE_LOG')\" = 1 ]"

reset have-toolkit current
run "$S/ygg-gpu.sh" setup
check "setup with all in place changes nothing: no dnf, no cdi generate" bash -c "[ $rc = 0 ] && ! grep -q -e 'dnf' -e 'cdi generate' '$FAKE_LOG'"
check "and it still runs the check" engine_ran

reset have-toolkit none
run "$S/ygg-gpu.sh" setup
check "setup with the toolkit and no spec only generates the spec" bash -c "[ $rc = 0 ] && ! grep -q 'dnf' '$FAKE_LOG' && grep -q 'cdi generate' '$FAKE_LOG'"

reset have-toolkit stale
run "$S/ygg-gpu.sh" setup
check "setup with a stale spec generates it again, without dnf" bash -c "[ $rc = 0 ] && ! grep -q 'dnf' '$FAKE_LOG' && grep -q 'cdi generate' '$FAKE_LOG' && grep -q 'gpu:' '$T/out'"
check "and the new spec names no gone folder" bash -c "! grep -q gone_c '$M/spec'"

# the engine is checked before any wsl.exe -d call (a wsl.exe -d boots a stopped distro)
reset no-toolkit none
FAKE_ENGINE_DOWN=1 run "$S/ygg-gpu.sh" setup
check "setup with an engine that does not answer exits 2 and made no wsl.exe -d call" bash -c "[ $rc = 2 ] && grep -q 'engine socket' '$T/out' && [ ! -s '$FAKE_LOG' ]"
reset have-toolkit current
FAKE_ENGINE_DOWN=1 run "$S/ygg-gpu.sh" check
check "check with an engine that does not answer made no wsl.exe -d call either" bash -c "[ $rc = 2 ] && [ ! -s '$FAKE_LOG' ]"

# state: a transport failure is not a missing state
reset have-toolkit current
FAKE_WSL_FAIL=1 run "$S/ygg-gpu.sh" check
check "check: a wsl.exe that fails is exit 2, not missing: toolkit" bash -c "[ $rc = 2 ] && ! grep -q 'missing' '$T/out'"
reset have-toolkit current
FAKE_WSL_FAIL=1 run "$S/ygg-gpu.sh" setup
check "setup: a wsl.exe that fails is exit 2, and installs and generates nothing" bash -c "[ $rc = 2 ] && ! grep -q -e dnf -e 'cdi generate' '$FAKE_LOG'"
reset have-toolkit current
FAKE_WSL_EMPTY=1 run "$S/ygg-gpu.sh" check
check "check: an empty answer from the probe is exit 2" bash -c "[ $rc = 2 ] && ! grep -q 'missing' '$T/out'"
reset have-toolkit none
printf 'devices:\n  path: /opt/other/x.so\n' >"$M/spec"
run "$S/ygg-gpu.sh" check
check "check: a spec that names no /usr/lib/wsl/drivers/ folder is stale" bash -c "[ $rc = 3 ] && grep -q -F 'missing: stale spec' '$T/out'"
reset have-toolkit stale
run "$S/ygg-gpu.sh" check --folder "$T/it2"
check "the printed fix keeps --folder when one was given" bash -c "grep -q -F -- 'fix: ' '$T/out' && grep -F 'fix: ' '$T/out' | grep -q -F -- '--folder $T/it2'"
reset have-toolkit stale
run "$S/ygg-gpu.sh" check
check "and the fix has no --folder when none was given" bash -c "grep -F 'fix: ' '$T/out' | grep -q -v -F -- '--folder'"
check "the probe is one script: the state function interpolates nothing into sh -c" bash -c "! grep -E 'root \"(cat|test -d)' '$S/ygg-gpu.sh'"

# the real wsl.exe expands $... in a command line: scripts go on stdin (sh -s), never as sh -c "$script"
check "root() sends scripts on stdin to sh -s, nothing on the command line" bash -c "! grep -q 'sh -c' '$S/ygg-gpu.sh' && grep -q 'sh -s' '$S/ygg-gpu.sh'"
reset have-toolkit current

run bash -c "printf '%s\n' 'x=1; echo \"[stdin \$x]\"' | '$T/bin/wsl.exe' -d podman-machine-default -u root -- sh -s"
check "the fake runs a stdin script unchanged" has "[stdin 1]"
# shellcheck disable=SC2016 # the $x must reach the fake unexpanded
run "$T/bin/wsl.exe" -d podman-machine-default -u root -- sh -c 'x=1; echo "[cmdline $x]"'
check "the fake loses \$x on the command line, as the real wsl.exe does" has "[cmdline ]"

# --- refusals: nothing changes
reset no-toolkit none
echo some-other-distro >"$M/distro"
run "$S/ygg-gpu.sh" setup
check "setup refuses when the machine has no WSL distro" bash -c "[ $rc != 0 ] && grep -q -i 'not a podman machine on wsl2' '$T/out'"
check "and changed nothing (no install, no generate)" bash -c "! grep -q -e dnf -e 'cdi generate' '$FAKE_LOG'"
reset no-toolkit none
run "$S/ygg-gpu.sh" setup --machine other
check "setup --machine NAME refuses a machine that has no distro" bash -c "[ $rc != 0 ] && grep -q -i 'not a podman machine on wsl2' '$T/out' && ! grep -q dnf '$FAKE_LOG'"
reset no-toolkit none
FAKE_NOMACHINE=1 run "$S/ygg-gpu.sh" setup
check "setup refuses when podman has no default machine" bash -c "[ $rc != 0 ] && grep -q -i 'not a podman machine on wsl2' '$T/out' && ! grep -q dnf '$FAKE_LOG'"
reset have-toolkit current
mkdir -p "$T/it"; printf 'sandbox:\n  engine: unix://%s/podman-sockets/podman-machine-default/podman-user.sock\n' "$T" >"$T/it/factory.yaml"
FAKE_NOMACHINE=1 run "$S/ygg-gpu.sh" check --folder "$T/it"
check "without podman machine inspect, the machine is the one the engine socket names" bash -c "[ $rc = 0 ] && grep -q 'gpu:' '$T/out'"
reset no-toolkit none
mv "$T/bin/wsl.exe" "$T/wsl.exe.off"
run "$S/ygg-gpu.sh" setup
check "setup refuses when wsl.exe is not there (not WSL2)" bash -c "[ $rc != 0 ] && grep -q -i 'not a podman machine on wsl2' '$T/out'"
mv "$T/wsl.exe.off" "$T/bin/wsl.exe"
run "$S/ygg-gpu.sh" frobnicate
check "an unknown mode prints usage and exits 2" bash -c "[ $rc = 2 ] && grep -q usage '$T/out'"

# --- the machine is never touched, and nothing runs as a privileged user through sudo
reset no-toolkit none
run "$S/ygg-gpu.sh" setup
check "setup never called sudo" bash -c "[ ! -e '$FAKE_LOG.sudo' ]"
check "and never started, stopped or re-created the machine" bash -c "! grep -q -E 'machine (start|stop|init|rm|reset|set)' '$FAKE_LOG.podman'"
check "and set no CONTAINER_HOST itself" bash -c "! grep -q CONTAINER_HOST '$S/ygg-gpu.sh'"

hermetic_done
echo; [ "$fail" -eq 0 ] && echo "ygg-gpu.test.sh: all ok" || echo "ygg-gpu.test.sh: FAILURES"
exit "$fail"

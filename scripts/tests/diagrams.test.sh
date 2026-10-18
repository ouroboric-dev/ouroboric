#!/usr/bin/env bash
# Tests for diagrams.sh.   scripts/tests/diagrams.test.sh
# A fake podman logs its calls and answers in-pod curl with an SVG; a fake host curl fails loudly.
# The pod must publish no host port: a stale DNAT rule from a crashed container can shadow a
# published port, and then every render fails while Kroki itself is healthy.
# shellcheck disable=SC2329  # the case functions are called by check
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../diagrams.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }

mkdir -p "$T/bin" "$T/repo/docs/assets/diagrams"
cat >"$T/bin/podman" <<'SH'
#!/usr/bin/env bash
echo "podman $*" >>"$LOG"
case "$1 ${2:-}" in
  "pod exists") [ -f "$STATE/pod" ] ;;
  "pod create") touch "$STATE/pod" ;;
  "exec "*) case " $* " in *" curl "*) cat >/dev/null; echo '<svg xmlns="http://www.w3.org/2000/svg"/>' ;; esac ;;
esac
SH
cat >"$T/bin/curl" <<'SH'
#!/usr/bin/env bash
echo "host-curl $*" >>"$LOG"; exit 7
SH
chmod +x "$T/bin/podman" "$T/bin/curl"
printf 'digraph { a -> b }\n' >"$T/repo/docs/assets/diagrams/g.dot"

run() { : >"$T/log"; LOG="$T/log" STATE="$T" PATH="$T/bin:$PATH" "$S" "$@" >/dev/null 2>&1; }

c_up() { rm -f -- "$T/pod"; run up && grep -q '^podman pod create' "$T/log"; }
c_noport() { ! grep -E '^podman pod create' "$T/log" | grep -qE ' (-p|--publish)( |=)'; }
c_render() { touch "$T/pod"; run render "$T/repo" && grep -q '<svg' "$T/repo/docs/assets/diagrams/rendered/g.svg"; }
c_inpod() { grep -q '^podman exec -i ouroboric-kroki-core curl' "$T/log" && ! grep -q '^host-curl' "$T/log"; }
c_check() { run check "$T/repo"; }

check "up creates the pod" c_up
check "the pod publishes no host port" c_noport
check "render writes the SVG" c_render
check "render reaches Kroki inside the pod, never over the host network" c_inpod
check "check passes after render" c_check
exit $fail

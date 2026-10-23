#!/usr/bin/env bash
# Tests for ygg-smoke-runtime.sh (gallery-runtime T26): the refusals, the order of the engine environment and
# podman, the shape of the commands, and the PASS and FAIL lines.   scripts/tests/ygg-smoke-runtime.test.sh
# A stand-in `podman` records its arguments and answers like a healthy product; a stand-in ygg-engine.sh loads a
# marker. No engine, no network, no key: the "key" of the stand-in is a made-up string that must never be printed.
# shellcheck disable=SC2329,SC2016 # check calls has and hasnt by name; the $ in the patterns is literal
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/.."
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
run() { "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
inlog() { grep -q -F -- "$1" "$T/calls"; }
notinlog() { ! grep -q -F -- "$1" "$T/calls"; }
export HOME="$T/home"; mkdir -p "$HOME"
unset YGG_ENGINE_CHECK

# The script under test sits next to a stand-in ygg-engine.sh, as in the tree.
mkdir -p "$T/tree/scripts" "$T/tree/yggdrasil"
cp "$S/ygg-smoke-runtime.sh" "$T/tree/scripts/"
cat >"$T/tree/scripts/ygg-engine.sh" <<'EOF2'
#!/usr/bin/env bash
echo "engine $*" >>"$FAKE_CALLS"
[ "${FAKE_ENGINE_FAIL:-}" != 1 ] || { echo "ygg-engine: the engine does not answer" >&2; exit 2; }
echo "export FAKE_ENGINE_LOADED=1"
EOF2
chmod +x "$T/tree/scripts/ygg-engine.sh"
SCRIPT="$T/tree/scripts/ygg-smoke-runtime.sh"

# The realms: only the three files the script needs.
Y="$T/ygg"
mkdir -p "$Y/helheim-go/templates/api" "$Y/midgard-react/templates/web" "$Y/niflheim-local/templates/product"
printf '#!/bin/sh\n' >"$Y/helheim-go/templates/api/release.sh"
printf '#!/bin/sh\n' >"$Y/midgard-react/templates/web/release.sh"
printf '#!/bin/bash\n' >"$Y/niflheim-local/templates/product/start.sh"
mkdir -p "$Y/midgard-react/templates/web/node_modules" "$Y/midgard-react/templates/web/dist"

# The stand-in podman: every call is one line in FAKE_CALLS (with whether the engine environment was loaded). It
# answers like a healthy product; FAKE_* switches break one thing.
mkdir -p "$T/bin"
cat >"$T/bin/podman" <<'EOF2'
#!/usr/bin/env bash
echo "podman loaded=${FAKE_ENGINE_LOADED:-0} $*" >>"$FAKE_CALLS"
a="$*"
case "$1" in
  image) [ "$FAKE_NO_IMAGE" = "${3:-}" ] && exit 1; exit 0 ;;
  images) echo "localhost/ygg-stack-x:abc" ;;
  inspect) echo "10.89.0.7" ;;
  logs) echo "start: weed stopped" ;;
  run)
    case "$a" in
      *"--entrypoint rm "*)
        for x in "$@"; do case "$x" in *:/w) rm -rf -- "${x%:/w}/app" ;; esac; done ;;
      *"--entrypoint /app/start.sh"*)
        for x in "$@"; do case "$x" in *:/app) [ -x "${x%:/app}/start.sh" ] || { echo "no start.sh" >&2; exit 126; } ;; esac; done ;;
      *release.sh*)
        [ "${FAKE_RELEASE_FAIL:-}" != 1 ] || { echo "go: build failed"; exit 1; }
        for x in "$@"; do case "$x" in *:/out) mkdir -p "${x%:/out}"; printf '#!/bin/sh\n' >"${x%:/out}/run.sh" ;; esac; done ;;
    esac ;;
  restart) [ "${FAKE_RESTART_LOSE:-}" != 1 ] || : >"$FAKE_STORE" ;;
  exec)
    case "$a" in
      *"cat /app/.ygg/release/repos/web/dist/index.html"*) echo "<html>bundle</html>" ;;
      *"cat /app/.data/seaweed-identity.json"*) echo '{"identities":[{"name":"app","credentials":[{"accessKey":"AKIAFAKEKEY","secretKey":"FAKESECRET123"}]}]}' ;;
      *"ss -ltnH"*) if [ "${FAKE_LISTEN_ALL:-}" = 1 ]; then printf '127.0.0.1:5432\n0.0.0.0:8080\n*:3000\n'; else printf '127.0.0.1:5432\n127.0.0.1:8333\n[::1]:9333\n*:3000\n'; fi ;;
      *"/dev/tcp/1.1.1.1"*) [ "${FAKE_ROUTE:-}" = 1 ] && exit 0; exit 1 ;;
      *"--aws-sigv4"*)
        case "$a" in
          *"-X PUT"*)
            prev=""
            for x in "$@"; do [ "$prev" = --data ] && printf '%s' "$x" >"$FAKE_STORE"; prev="$x"; done
            printf '%s' "${FAKE_PUT_CODE:-200}" ;;
          *) printf '%s' "$(cat "$FAKE_STORE" 2>/dev/null)" ;;
        esac ;;
      *curl*)
        case "$a" in
          *"-X PUT"*) printf '%s' "${FAKE_UNSIGNED_CODE:-403}" ;;
          *"/api/healthz"*) printf '200' ;;
          *"-o /dev/null"*) [ "${FAKE_NO_ANSWER:-}" = 1 ] && printf '000' || printf '200' ;;
          *) if [ "${FAKE_INDEX_DIFF:-}" = 1 ]; then echo "<html>other</html>"; else echo "<html>bundle</html>"; fi ;;
        esac ;;
    esac ;;
esac
exit 0
EOF2
chmod +x "$T/bin/podman"
# The engine sees the folder at the bind mount (a link here), as the Podman machine does.
export YGG_BIND="$T/bind"
export PATH="$T/bin:$PATH" FAKE_CALLS="$T/calls" FAKE_STORE="$T/store"
D="$T/it"; mkdir -p "$D"; ln -s "$D" "$YGG_BIND"
runit() { : >"$T/calls"; : >"$T/store"; run "$SCRIPT" --folder "$D" --yggdrasil "$Y" --image task:img --api-image api:img --web-image web:img "$@"; }

# Refusals.
runit --nope; check "an unknown option is refused (exit 2)" test "$rc" = 2
run "$SCRIPT" --folder "$D" --yggdrasil "$T/none" --image task:img
check "a missing yggdrasil folder is refused with a message" bash -c "[ $rc = 2 ] && grep -q 'no yggdrasil folder' '$T/out'"
mv "$Y/niflheim-local/templates/product/start.sh" "$T/start.sh.kept"
runit; check "a missing realm file is refused, naming it" bash -c "[ $rc = 2 ] && grep -q 'niflheim-local/templates/product/start.sh is missing' '$T/out'"
check "a missing realm file starts nothing" notinlog "podman"
mv "$T/start.sh.kept" "$Y/niflheim-local/templates/product/start.sh"
FAKE_NO_IMAGE=task:img runit; check "a missing image is refused with a message" bash -c "[ $rc = 2 ] && grep -q 'image task:img is missing' '$T/out'"
check "a missing image makes no network" notinlog "network create"
FAKE_ENGINE_FAIL=1 runit; check "an engine that does not answer stops the script before any podman" bash -c "[ $rc = 2 ]"
check "... and podman was never called" notinlog "podman "
FAKE_RELEASE_FAIL=1 runit; check "a failed release stops with its output and no product" bash -c "[ $rc = 2 ] && grep -q 'go: build failed' '$T/out' && grep -q 'release failed' '$T/out'"
check "... and no network was made" notinlog "network create"

# A healthy run.
runit
check "a healthy run exits 0" test "$rc" = 0
for c in "index: GET / answers" "api: GET /api/healthz" "unsigned: an unsigned PUT" "signed: a signed PUT" "listeners: every listener" "no-route:" "restart: start.sh found"; do
  check "PASS line: $c" has "PASS  $c"
done
check "no FAIL line" hasnt "FAIL"
check "the time to the first answer is printed" bash -c "grep -Eq '^TIME  the first answer came [0-9]+ s after the start' '$T/out'"
check "the engine environment is loaded first" bash -c "head -n 1 '$T/calls' | grep -q '^engine env --folder $D'"
check "podman runs only after the environment is loaded" bash -c "grep -c '^podman loaded=0' '$T/calls' | grep -qx 0 && grep -q '^podman loaded=1' '$T/calls'"
check "each release is built by its release.sh in its realm's image" bash -c "grep -q 'podman loaded=1 run --rm -v .*-e OUT=/out .* api:img sh /src/release.sh' '$T/calls' && grep -q 'web:img sh /src/release.sh' '$T/calls'"
check "the network is internal" inlog "network create --internal smoke-runtime-"
check "the product runs in the task image as app on that network" bash -c "grep -E 'run -d --name smoke-runtime-product-[0-9]+ --network smoke-runtime-[0-9]+ --user app --entrypoint /app/start.sh .* task:img' '$T/calls' | grep -q ."
check "the checks run from a second container on the same network" bash -c "grep -q 'run -d --name smoke-runtime-check-[0-9]* --network smoke-runtime-[0-9]*' '$T/calls' && grep -q 'exec smoke-runtime-check-[0-9]* curl' '$T/calls'"
check "the checks go to the product's address on port 3000" inlog "http://10.89.0.7:3000/api/healthz"
check "the signed requests use SigV4 for s3 in us-east-1" inlog "aws:amz:us-east-1:s3"
check "the product is restarted in the same container" bash -c "grep -Eq 'restart --time 30 smoke-runtime-product-' '$T/calls'"
check "both containers and the network are removed" bash -c "grep -q 'rm -f smoke-runtime-product-' '$T/calls' && grep -q 'smoke-runtime-check-[0-9]*' '$T/calls' && grep -q 'network rm -f smoke-runtime-' '$T/calls'"
check "the key is never printed" bash -c "! grep -q 'FAKESECRET\|AKIAFAKEKEY' '$T/out'"
check "the key is never in an argument" notinlog "FAKESECRET"
check "the access key is never in an argument" notinlog "AKIAFAKEKEY"
check "the work folder is gone" bash -c "! ls '$D' | grep -q smoke-runtime-"
check "it never names hidden-suites or a credentials file" bash -c "! grep -qi 'hidden-suites\|factory.env\|huldra' '$SCRIPT'"

check "every -v source starts with the bind mount" bash -c "grep -oE -- '-v /[^ ]+' '$T/calls' | grep -qv -- '-v $YGG_BIND/' && exit 1; grep -q -- '-v $YGG_BIND/' '$T/calls'"
check "no -v source is a host path under the folder" bash -c "! grep -E -- '-v $D' '$T/calls'"
check "every curl runs in the checker container" bash -c "! grep -E '^podman loaded=1 exec' '$T/calls' | grep curl | grep -v 'smoke-runtime-check-[0-9]'"
check "the chown of /app is a root run in the task image, on the bind path" bash -c "grep -Eq 'run --rm --user root --entrypoint chown -v $YGG_BIND/smoke-runtime-[0-9-]+/app:/app task:img -R app:app /app' '$T/calls'"
check "the cleanup removes app in a root container, before the host rm" bash -c "grep -Eq 'run --rm --user root --entrypoint rm -v $YGG_BIND/smoke-runtime-[0-9-]+:/w task:img -rf /w/app' '$T/calls'"
check "unshare is never used" notinlog "unshare"
check "both containers go in one rm -f, product first" bash -c "grep -Eq 'rm -f smoke-runtime-product-([0-9]+) smoke-runtime-check-\\1\$' '$T/calls'"
check "the key is read as app" bash -c "grep -Eq 'exec --user app smoke-runtime-product-[0-9]+ cat /app/.data/seaweed-identity.json' '$T/calls'"
check "signed requests send the unsigned-payload header" inlog "x-amz-content-sha256: UNSIGNED-PAYLOAD"
check "no-route has a positive control that connects" bash -c "grep -Eq 'exec smoke-runtime-product-[0-9]+ timeout 5 bash -c .*/dev/tcp/10.89.0.7/3000' '$T/calls'"

# One thing broken at a time.
FAKE_UNSIGNED_CODE=200 runit; check "an unsigned PUT that is accepted fails" bash -c "[ $rc = 1 ] && grep -q 'FAIL  unsigned' '$T/out'"
FAKE_PUT_CODE=500 runit; check "a signed PUT that fails, fails" bash -c "[ $rc = 1 ] && grep -q 'FAIL  signed' '$T/out'"
FAKE_LISTEN_ALL=1 runit; check "a listener on 0.0.0.0 that is not 3000 fails, with a count" bash -c "[ $rc = 1 ] && grep -q 'FAIL  listeners.*1 not on loopback' '$T/out'"
FAKE_ROUTE=1 runit; check "an outside address that answers fails" bash -c "[ $rc = 1 ] && grep -q 'FAIL  no-route' '$T/out'"
FAKE_INDEX_DIFF=1 runit; check "an index that is not the bundle's fails" bash -c "[ $rc = 1 ] && grep -q 'FAIL  index' '$T/out'"
FAKE_RESTART_LOSE=1 runit; check "an object lost by the restart fails" bash -c "[ $rc = 1 ] && grep -q 'FAIL  restart' '$T/out'"
FAKE_NO_ANSWER=1 YGG_SMOKE_WAIT=2 runit; check "a product that never answers fails after the wait, with every check named" bash -c "[ $rc = 1 ] && grep -q 'FAIL  index' '$T/out' && grep -q 'FAIL  restart' '$T/out'"
check "... and nothing is left: the network is removed" inlog "network rm -f smoke-runtime-"

[ "$fail" -eq 0 ] || exit 1
echo "all ok"

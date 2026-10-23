#!/usr/bin/env bash
# Run the runtime smoke (gallery-runtime T26/T30): a product made from the templates, started by Niflheim's product
# start, in the task image, on an internal Podman network, as the user `app`, and checked from a second container.
#   ygg-smoke-runtime.sh [--image REF] [--folder DIR] [--yggdrasil DIR] [--api-image REF] [--web-image REF]
# --image is the task image (default localhost/client-gallery-lite:latest: build it from mimir's
# client-gallery-lite/environment). --yggdrasil is the folder that holds helheim-go, midgard-react and niflheim-local
# (default: the yggdrasil folder next to this repo in the umbrella). --api-image and --web-image are the sandbox
# images of helheim-go and midgard-react (default: the newest localhost/ygg-stack-<realm> image `ygg sandbox build`
# made). DIR (default $HOME/ygg-it) holds factory.yaml; the engine environment comes from ygg-engine.sh
# (YGG_ENGINE_CHECK=0 skips it), never a bare podman on the root socket. The script
#   1. refuses a missing realm file or a missing image, with a message;
#   2. builds each template's release with its release.sh in that realm's sandbox image (api, then web);
#   3. makes a folder laid out like /app: niflheim-local's start.sh at its root, the two releases under
#      .ygg/release/repos/<leaf>/, an empty repos/api and repos/web, all owned by `app`;
#   4. makes a Podman network with --internal (an address, and no route out), runs the product in the task image on
#      it with --user app, and a second container on the same network that makes the requests;
#   5. checks, each printed as PASS or FAIL, in this order:
#        index     GET / on port 3000 answers the bundle's index.html within 2 minutes (the time is printed);
#        api       GET /api/healthz answers 200 from the API through port 3000;
#        unsigned  an unsigned PUT to /ygg-store/x through port 3000 is refused (4xx);
#        signed    a signed PUT and GET (curl --aws-sigv4; the key is read as `app` from /app/.data and is never
#                  printed) through port 3000 succeed;
#        listeners every listener except :3000 is bound to loopback (ss -ltn, or /proc/net/tcp);
#        no-route  the product container cannot reach an outside address (after a control: it reaches its own);
#        restart   a restart of start.sh in the same container finds the object written before (the time is printed);
#   6. removes both containers, the network and the work folder, whatever the result.
# The newest localhost/ygg-stack-<realm> image may be stale (an older build of the realm): pass --api-image and
# --web-image to name the images. The default --yggdrasil needs the umbrella's submodules at their merged main
# (helheim-go's release.sh, niflheim-local's start.sh). Paths given to the engine are mapped to its bind mount
# (YGG_BIND, default /mnt/wsl/ygg-bind) as ygg-smoke-grade.sh does, so DIR must be under it. YGG_SMOKE_WAIT is the
# wait for port 3000 in seconds (default 120; for tests).
# Exit 0 only when every check passes.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="$HOME/ygg-it" image="localhost/client-gallery-lite:latest" ygg="$HERE/../../yggdrasil" api_image="" web_image=""
usage() { echo "usage: ygg-smoke-runtime.sh [--image REF] [--folder DIR] [--yggdrasil DIR] [--api-image REF] [--web-image REF]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --image) [ $# -ge 2 ] || usage; image="$2"; shift 2 ;;
    --folder) [ $# -ge 2 ] || usage; dir="$2"; shift 2 ;;
    --yggdrasil) [ $# -ge 2 ] || usage; ygg="$2"; shift 2 ;;
    --api-image) [ $# -ge 2 ] || usage; api_image="$2"; shift 2 ;;
    --web-image) [ $# -ge 2 ] || usage; web_image="$2"; shift 2 ;;
    *) usage ;;
  esac
done
fail() { echo "smoke-runtime: $*" >&2; exit 2; }

ygg="$(cd "$ygg" 2>/dev/null && pwd)" || fail "no yggdrasil folder at $ygg (--yggdrasil)"
api_src="$ygg/helheim-go/templates/api" web_src="$ygg/midgard-react/templates/web" start_src="$ygg/niflheim-local/templates/product/start.sh"
for f in "$api_src/release.sh" "$web_src/release.sh" "$start_src"; do
  [ -f "$f" ] || fail "$f is missing; --yggdrasil must hold helheim-go, midgard-react and niflheim-local (the realms at the merged main)"
done

if [ "${YGG_ENGINE_CHECK:-1}" = 1 ]; then
  engine_env="$("$HERE/ygg-engine.sh" env --folder "$dir")" || exit 2
  eval "$engine_env"
fi
command -v podman >/dev/null 2>&1 || fail "podman is not installed"
# The newest image is the first line. sed reads every line: head would close the pipe early, and podman's SIGPIPE
# would then fail the pipeline (pipefail) and stop the script with 141 and no message.
stack() { podman images --filter "reference=localhost/ygg-stack-$1" --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | sed -n 1p; }
[ -n "$api_image" ] || api_image="$(stack helheim-go)"
[ -n "$web_image" ] || web_image="$(stack midgard-react)"
[ -n "$api_image" ] || fail "no sandbox image of helheim-go; build it with 'ygg sandbox build --realm helheim-go' or pass --api-image"
[ -n "$web_image" ] || fail "no sandbox image of midgard-react; build it with 'ygg sandbox build --realm midgard-react' or pass --web-image"
for i in "$image" "$api_image" "$web_image"; do
  podman image exists "$i" || fail "the image $i is missing from the engine"
done

id="$$" work="$dir/smoke-runtime-$(date +%Y%m%d-%H%M%S)" net="smoke-runtime-$$" prod="smoke-runtime-product-$$" chk="smoke-runtime-check-$$"
app="$work/app"
# eng PATH: where the engine (the Podman machine) sees a path under DIR: at the bind mount, as ygg-smoke-grade.sh does.
bind="${YGG_BIND:-/mnt/wsl/ygg-bind}"
eng() { echo "$bind${1#"$dir"}"; }
cleanup() {
  podman rm -f -v "$prod" "$chk" >/dev/null 2>&1 || true
  podman network rm -f "$net" >/dev/null 2>&1 || true
  # The files of app belong to a mapped user the host cannot remove: a root container in the engine does it.
  podman run --rm --user root --entrypoint rm -v "$(eng "$work"):/w" "$image" -rf /w/app >/dev/null 2>&1 || true
  rm -rf -- "$work" 2>/dev/null || true
}
trap cleanup EXIT
mkdir -p "$app/.ygg/release/repos/api" "$app/.ygg/release/repos/web" "$app/repos/api" "$app/repos/web" "$work/build"
echo "smoke-runtime: made $work"

release() { # release LEAF IMAGE SRC: build the template's release into app/.ygg/release/repos/LEAF
  local leaf="$1" img="$2" src="$3" b="$work/build/$1"
  cp -R "$src" "$b"
  rm -rf -- "$b/node_modules" "$b/dist"
  echo "smoke-runtime: building the $leaf release in $img"
  podman run --rm -v "$(eng "$b"):/src" -v "$(eng "$app/.ygg/release/repos/$leaf"):/out" -e OUT=/out -w /src "$img" sh /src/release.sh >"$work/build-$leaf.txt" 2>&1 \
    || { sed 's/^/  | /' "$work/build-$leaf.txt" >&2; fail "the $leaf release failed (see above)"; }
  [ -f "$app/.ygg/release/repos/$leaf/run.sh" ] || fail "the $leaf release.sh wrote no run.sh"
}
release api "$api_image" "$api_src"
release web "$web_image" "$web_src"
cp "$start_src" "$app/start.sh"
cmp -s "$start_src" "$app/start.sh" || fail "start.sh at the root of the app folder is not niflheim-local's templates/product/start.sh"
chmod 755 "$app/start.sh"
podman run --rm --user root --entrypoint chown -v "$(eng "$app"):/app" "$image" -R app:app /app

podman network create --internal "$net" >/dev/null
podman run -d --name "$prod" --network "$net" --user app --entrypoint /app/start.sh -v "$(eng "$app"):/app" -w /app "$image" >/dev/null
podman run -d --name "$chk" --network "$net" --user app --entrypoint sleep "$image" infinity >/dev/null
start=$SECONDS
ip() { podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$prod"; }
get() { podman exec "$chk" curl -s --max-time 10 "$@"; } # get CURL-ARGS...: the body
code() { podman exec "$chk" curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" || true; } # code CURL-ARGS...
# key: print the access and the secret key of the identity file, read as `app`, as "ACCESS SECRET" on stdout. The
# caller keeps them in variables and never prints them.
key() {
  podman exec --user app "$prod" cat /app/.data/seaweed-identity.json \
    | tr -d '\n' | sed -n 's/.*"accessKey":"\([^"]*\)".*"secretKey":"\([^"]*\)".*/\1 \2/p'
}
signed() { # signed URL CURL-ARGS...: curl with the key, which goes through the environment, not the arguments
  local url="$1" ak sk
  shift
  read -r ak sk < <(key)
  AK="$ak" SK="$sk" podman exec -e AK -e SK "$chk" sh -c 'u="$1"; shift; curl -s --max-time 10 -H "x-amz-content-sha256: UNSIGNED-PAYLOAD" --aws-sigv4 "aws:amz:us-east-1:s3" --user "$AK:$SK" "$@" "$u"' sh "$url" "$@"
}
wait_index() { # wait_index: seconds until / answers, or empty after 2 minutes
  local t=$SECONDS
  while [ $((SECONDS - t)) -lt "${YGG_SMOKE_WAIT:-120}" ]; do
    if [ "$(code "http://$(ip):3000/")" = 200 ]; then echo $((SECONDS - t)); return 0; fi
    sleep 2
  done
  return 1
}

bad=0
set +e # a failed check is a FAIL line, not the end
result() { # result DESCRIPTION COMMAND...: PASS when the command succeeds
  local d="$1"
  shift
  if "$@"; then echo "PASS  $d"; else echo "FAIL  $d"; bad=1; fi
}
same() { [ "$1" = "$2" ]; }
refused() { case "$1" in 4??) true ;; *) false ;; esac; }
put_ok() { [ "$1" = 200 ] && [ "$2" = "$3" ]; } # put_ok CODE GOT WANT
outside_fails() { # a control first: the same probe to the product's own address must connect, or the probe proves nothing
  podman exec "$prod" timeout 5 bash -c "exec 3<>/dev/tcp/$(ip)/3000" >/dev/null 2>&1 || return 1
  ! podman exec "$prod" timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/80' >/dev/null 2>&1; }
lacks() { [ -n "$1" ] && [ -z "$2" ]; } # lacks LISTENERS OTHERS

body="smoke-$id-$RANDOM"
if t="$(wait_index)"; then
  want="$(podman exec "$prod" cat /app/.ygg/release/repos/web/dist/index.html)"
  got="$(get "http://$(ip):3000/")"
  result "index: GET / answers the bundle's index.html (after $t s)" same "$got" "$want"
  echo "TIME  the first answer came $((SECONDS - start)) s after the start"
  result "api: GET /api/healthz answers 200 through port 3000" same "$(code "http://$(ip):3000/api/healthz")" 200
  c="$(code -X PUT --data x "http://$(ip):3000/ygg-store/x")"
  result "unsigned: an unsigned PUT to /ygg-store/x is refused (${c:-none})" refused "$c"
  # The API makes the bucket; this makes it only when it is not there (the answer is not checked).
  signed "http://$(ip):3000/ygg-store" -X PUT -o /dev/null
  pc="$(signed "http://$(ip):3000/ygg-store/$body" -X PUT --data "$body" -o /dev/null -w '%{http_code}')"
  gb="$(signed "http://$(ip):3000/ygg-store/$body")"
  result "signed: a signed PUT (${pc:-none}) and GET of ygg-store/$body through port 3000" put_ok "$pc" "$gb" "$body"
  # shellcheck disable=SC2016
  listeners="$(podman exec "$prod" sh -c 'if command -v ss >/dev/null 2>&1; then ss -ltnH | awk "{print \$4}"; else cat /proc/net/tcp /proc/net/tcp6 | awk "\$4 == \"0A\" {print \$2}"; fi')"
  other="$(printf '%s\n' "$listeners" | grep -vE '^(127\.0\.0\.1|\[::1\]|0100007F|00000000000000000000000001000000):' | grep -vE ':(3000|0BB8)$')"
  result "listeners: every listener except :3000 is on loopback ($(printf '%s\n' "$listeners" | grep -c .) listeners, $(printf '%s\n' "$other" | grep -c .) not on loopback)" lacks "$listeners" "$other"
  result "no-route: the product container cannot reach an outside address" outside_fails
  rstart=$SECONDS
  podman restart --time 30 "$prod" >/dev/null
  if wait_index >/dev/null; then
    gb="$(signed "http://$(ip):3000/ygg-store/$body")"
    result "restart: start.sh found ygg-store/$body again (port 3000 after $((SECONDS - rstart)) s)" same "$gb" "$body"
  else
    result "restart: port 3000 answered within 2 minutes after the restart" false
  fi
else
  result "index: port 3000 answered within 2 minutes" false
  echo "smoke-runtime: the end of the product's output:" >&2
  podman logs --tail 30 "$prod" 2>&1 | sed 's/^/  | /' >&2
  for n in api unsigned signed listeners no-route restart; do result "$n: ran (the product never answered)" false; done
fi
echo
if [ "$bad" -ne 0 ]; then echo "smoke-runtime: a check failed"; exit 1; fi
echo "smoke-runtime: every check passed"

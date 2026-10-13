#!/usr/bin/env bash
# Scan the full git history of repos for secrets, with the pinned gitleaks image. Agent-run.
# Each repo goes in as a git bundle: that carries a submodule's history too, and works with a
# Podman machine that can't mount WSL paths. The container gets no network, and the host's registry
# credentials are never used (spec §16 item 7). Findings are redacted.
#   scan-history.sh <repo dir>...      prints "clean", "LEAKS" or "ERROR" per repo; exits 1 if any isn't clean
set -uo pipefail
# Bump through a reviewed PR. The image must be at least two weeks old when pinned.
IMAGE="docker.io/zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"
[ $# -ge 1 ] || { echo "usage: scan-history.sh <repo dir>..." >&2; exit 2; }

A="$(mktemp -d)"
trap 'rm -rf -- "${A:?}"' EXIT
echo '{}' > "$A/auth.json"
export REGISTRY_AUTH_FILE="$A/auth.json" DOCKER_CONFIG="$A"
podman image exists "$IMAGE" || podman pull -q --authfile "$A/auth.json" "$IMAGE" >/dev/null \
  || { echo "scan-history: can't pull $IMAGE" >&2; exit 2; }

fail=0
for d in "$@"; do
  if ! git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then echo "ERROR $d"; fail=1; continue; fi
  # Inside: exit 3 if the bundle can't be cloned; gitleaks exits 1 on leaks and 0 when clean.
  git -C "$d" bundle create - --all 2>/dev/null \
    | podman run --rm -i --pull=never --network=none --entrypoint sh "$IMAGE" \
        -c 'cat > /tmp/r.bundle && git clone -q /tmp/r.bundle /r || exit 3; gitleaks git /r --no-banner --redact' \
        > "$A/report" 2>&1
  case "${PIPESTATUS[1]}" in
    0) echo "clean $d" ;;
    1) echo "LEAKS $d"; cat "$A/report"; fail=1 ;;
    *) echo "ERROR $d"; cat "$A/report"; fail=1 ;;
  esac
done
exit $fail

#!/usr/bin/env bash
# Tests for ygg-engine.sh.   scripts/tests/ygg-engine.test.sh
# A fake `podman` and a fake `devcontainer` stand in for the real tools: no engine, no network.
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
export HOME="$T/home"; mkdir -p "$HOME"

# A unix socket the script can find, a folder with a factory.yaml that names it, and a bind mount folder.
SOCK="$T/user.sock"
python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$SOCK"
D="$T/it"; mkdir -p "$D" "$T/bind"
cat > "$D/factory.yaml" <<YAML
sandbox:
  engine: unix://$SOCK
  mounts:
    - { host: $D, engine: $T/bind }
YAML
# Fakes: podman answers `info` from $FAKE_ROOTLESS (true by default) or hangs when FAKE_HANG is set;
# devcontainer prints $FAKE_CLI (0.89.0 by default).
mkdir -p "$T/bin"
cat > "$T/bin/podman" <<'EOF2'
#!/usr/bin/env bash
[ -z "${FAKE_HANG:-}" ] || sleep 30
echo "${FAKE_ROOTLESS:-true}"
EOF2
cat > "$T/bin/devcontainer" <<'EOF2'
#!/usr/bin/env bash
echo "${FAKE_CLI:-0.89.0}"
EOF2
chmod +x "$T/bin/podman" "$T/bin/devcontainer"
export PATH="$T/bin:$PATH" YGG_BIND="$T/bind" YGG_ENGINE_TIMEOUT=2

run bash "$S/ygg-engine.sh" check --folder "$D"
check "check passes on a rootless engine, the right CLI and the bind mount, and says what it found" \
  bash -c "[ $rc = 0 ]" && has "answers and is rootless" && has "devcontainer CLI 0.89.0"

CONTAINER_HOST=unix:///run/podman/podman-root.sock DOCKER_HOST=tcp://x run bash "$S/ygg-engine.sh" env --folder "$D"
check "env replaces an ambient CONTAINER_HOST with the engine of factory.yaml, and unsets DOCKER_HOST" \
  bash -c "[ $rc = 0 ] && grep -q 'CONTAINER_HOST=unix:..$T/user.sock' '$T/out' && grep -q 'unset CONTAINER_CONNECTION DOCKER_HOST' '$T/out' && ! grep -q 'podman-root' '$T/out'"
check "env points the credential helper config and the auth file at empty files, made on the way" \
  bash -c "grep -q 'DOCKER_CONFIG=$D/empty-docker' '$T/out' && [ \"\$(cat '$D/empty-docker/config.json')\" = '{}' ] && [ \"\$(cat '$D/empty-auth.json')\" = '{}' ]"
check "env puts the devcontainer CLI folder of the work folder first on PATH" \
  bash -c "grep -q 'PATH=$D/dc/node_modules/.bin' '$T/out'"

CONTAINER_HOST=unix:///run/podman/podman-root.sock run bash "$S/ygg-engine.sh" run --folder "$D" -- bash -c 'echo "$CONTAINER_HOST|$DOCKER_CONFIG|${DOCKER_HOST-unset}"'
check "run runs the command in that environment" \
  bash -c "grep -qx 'unix://$SOCK|$D/empty-docker|unset' '$T/out'"

FAKE_ROOTLESS=false run bash "$S/ygg-engine.sh" check --folder "$D"
check "check refuses an engine that is not rootless" bash -c "[ $rc = 2 ]" && has "is not rootless"

FAKE_HANG=1 run bash "$S/ygg-engine.sh" check --folder "$D"
check "check gives up on an engine that does not answer, and says to ask before restarting" \
  bash -c "[ $rc = 2 ]" && has "did not answer in 2s" && has "Ask before restarting"

FAKE_CLI=0.90.0 run bash "$S/ygg-engine.sh" check --folder "$D"
check "check refuses another devcontainer CLI version" bash -c "[ $rc = 2 ]" && has "want 0.89.0"

YGG_BIND="$T/nowhere" run bash "$S/ygg-engine.sh" check --folder "$D"
check "check refuses a missing bind mount" bash -c "[ $rc = 2 ]" && has "bind mount"

D2="$T/other"; mkdir -p "$D2"; printf 'sandbox:\n  engine: unix://%s/gone.sock\n' "$T" > "$D2/factory.yaml"
run bash "$S/ygg-engine.sh" check --folder "$D2"
check "check names a socket that is not there" bash -c "[ $rc = 2 ]" && has "gone.sock is not there"

printf 'sandbox:\n  engine: tcp://x\n' > "$D2/factory.yaml"
run bash "$S/ygg-engine.sh" check --folder "$D2"
check "check refuses an engine that is not a unix:// URL" bash -c "[ $rc = 2 ]" && has "must be a unix:// URL"

run bash "$S/ygg-engine.sh" check --folder "$T/none"
check "check names a work folder with no factory.yaml" bash -c "[ $rc = 2 ]" && has "factory.yaml is missing"

run bash "$S/ygg-engine.sh" run --folder "$D"
check "run without a command is a usage error" bash -c "[ $rc = 2 ]" && has "usage:"

exit $fail

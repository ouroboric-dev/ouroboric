#!/usr/bin/env bash
# Tests for ygg-events-watch.sh.   scripts/tests/ygg-events-watch.test.sh
# A fake `podman events` process stands in for the real one: it writes 5 bytes to a pipe that nobody reads.
# shellcheck disable=SC2216,SC2329 # the reader that never reads is the point; has() is called through check
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/.."
T="$(mktemp -d)"
trap 'kill "${fake:-0}" 2>/dev/null; rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
run() { "$@" >"$T/out" 2>&1; rc=$?; }
has() { grep -q -F -- "$1" "$T/out"; }

cat > "$T/podman" <<'EOF2'
#!/usr/bin/env bash
printf 'hello'
sleep 30
EOF2
chmod +x "$T/podman"

# No events process: the watcher says so and ends after its samples.
run "$S/ygg-events-watch.sh" --interval 0.1 --count 2
check "no events process is reported and exits 0" test "$rc" -eq 0 -a "$(grep -c 'no events process' "$T/out")" -eq 2

# One events process whose output nobody reads: the unread bytes and the bytes written are shown.
"$T/podman" events --format json --filter event=start 2>/dev/null | sleep 30 &
sleep 0.5
fake="$(pgrep -f 'podman events --format json --filter event=start' | head -n 1)"
run "$S/ygg-events-watch.sh" --interval 0.1 --count 1
check "the process is listed with its pid" has "pid=$fake "
if [ -r /proc/self/io ]; then
  check "wchar counts what it wrote" has "wchar=5"
else
  check "wchar is n/a where /proc/PID/io is missing" has "wchar=n/a"
fi
check "unread bytes of its stdout pipe are shown" has "unread=5"
check "a log file receives the same lines" bash -c "run() { :; }; '$S/ygg-events-watch.sh' --interval 0.1 --count 1 --log '$T/log' >/dev/null 2>&1; grep -q 'pid=$fake ' '$T/log'"

# Bad usage.
run "$S/ygg-events-watch.sh" --bogus
check "an unknown option exits 2" test "$rc" -eq 2

exit "$fail"

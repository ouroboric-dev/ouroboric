#!/usr/bin/env bash
# Watch the `podman events` process that the devcontainer CLI starts, to find out why `devcontainer up` hangs
# (backlog B-051). Start it BEFORE the run, in a second terminal, and let it sample until the run ends:
#   ygg-events-watch.sh [--interval SECONDS] [--count N] [--log FILE]
# Every INTERVAL seconds (default 2) it prints one line for each process whose command line holds
# `events --format json --filter event=start`, or says there is none:
#   pid        the process, and ppid its parent (the CLI)
#   age        seconds since it started
#   wchan      what the kernel has it waiting on (futex_do_wait: waiting for a wake-up)
#   rchar      bytes it has read, wchar the bytes it has written (/proc/PID/io): wchar 0 at a hang means
#              podman wrote no event; wchar above 0 with unread above 0 means the CLI does not read what was written
#   unread     bytes in its stdout pipe or socket that the reader (the CLI) has not read yet
# With --count N it ends after N samples. With --log FILE the lines are also appended to FILE.
set -uo pipefail
interval=2 count=0 log=""
usage() { echo "usage: ygg-events-watch.sh [--interval SECONDS] [--count N] [--log FILE]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --interval) interval="${2:?--interval needs a number}"; shift 2 ;;
    --count) count="${2:?--count needs a number}"; shift 2 ;;
    --log) log="${2:?--log needs a file}"; shift 2 ;;
    *) usage ;;
  esac
done
pattern='events --format json --filter event=start'
out() { printf '%s\n' "$1"; [ -z "$log" ] || printf '%s\n' "$1" >>"$log"; }
# unread BYTES for the stdout of PID: a pipe answers FIONREAD, a socket pair shows them as Send-Q in ss.
unread() {
  local link inode
  link="$(readlink "/proc/$1/fd/1" 2>/dev/null || true)"
  case "$link" in
    pipe:*) python3 -I -c 'import fcntl, os, struct, sys, termios
fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NONBLOCK)
print(struct.unpack("i", fcntl.ioctl(fd, termios.FIONREAD, b"\0\0\0\0"))[0])' "/proc/$1/fd/1" 2>/dev/null || echo n/a ;;
    socket:*)
      inode="${link#socket:[}"; inode="${inode%]}"
      ss -xnH 2>/dev/null | awk -v i="$inode" '$6 == i { print $4; found = 1 } END { if (!found) print "n/a" }' | head -n 1 ;;
    *) echo n/a ;;
  esac
}
# io PID FIELD: a field of /proc/PID/io, n/a where the kernel or a sandbox does not offer the file.
io() { sed -n "s/^$2: //p" "/proc/$1/io" 2>/dev/null | grep . || echo n/a; }
n=0
while :; do
  n=$((n + 1))
  now="$(date -u +%FT%TZ)"
  pids="$(pgrep -f -- "$pattern" || true)"
  if [ -z "$pids" ]; then
    out "$now no events process"
  else
    for pid in $pids; do
      [ -r "/proc/$pid/stat" ] || continue
      ppid="$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || true)"
      age="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
      out "$now pid=$pid ppid=${ppid:-?} age=${age:-?}s wchan=$(cat "/proc/$pid/wchan" 2>/dev/null || echo ?) rchar=$(io "$pid" rchar) wchar=$(io "$pid" wchar) unread=$(unread "$pid")"
    done
  fi
  [ "$count" -eq 0 ] || [ "$n" -lt "$count" ] || break
  sleep "$interval"
done
exit 0

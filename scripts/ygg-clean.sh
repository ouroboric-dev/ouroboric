#!/usr/bin/env bash
# Clean up after runs that have ended: `ygg doctor` on each project, which removes the empty pods and the
# leftover containers of that project's runs.
#   ygg-clean.sh [--dry-run] [--folder DIR] [--keep PROJECT]... [PROJECT...]
# The projects are the PROJECTs named, or every folder that holds .factory/runs at DIR, DIR/NAME or DIR/NAME/SUB
# (default DIR $HOME/ygg-it), so DIR/smoke-real-TIME/project and DIR/proof-NAME-TIME/project. DIR/hidden-suites and
# DIR/dc are never entered. A PROJECT (and a --keep) is a name under DIR, else a folder. --keep P also keeps every
# project inside the folder P, so `--keep DIR/proof-r1-X` keeps that proof run's project. A PROJECT or --keep under
# DIR/hidden-suites is refused by its path, before the folder is entered.
#   * A project is skipped when a run of it is live, and the summary says which, by either of two checks: a FLOCK
#     line in /proc/locks for a run's lock or the project's runs lock (as odin's lock.Held reads it), or a process
#     with one of those lock files open (its /proc/PID/fd links: ygg keeps a lock file open while it holds it). The
#     checks never take a lock and never signal a process. When the locks file or /proc cannot be read, the script
#     cannot tell whether a run is live, so it refuses (exit 2) before any doctor runs.
#   * The config is the one a run recorded (config_path in its run.json, newest run first), else PROJECT/factory.yaml
#     or factory.yaml beside the project. A project with no config is skipped with a message.
#   * It runs `ygg doctor --project P --config C` (YGG_CMD, default ygg), with the engine environment of
#     ygg-engine.sh (YGG_ENGINE_CHECK=0 skips it). The summary lists the projects cleaned, kept, skipped (and why)
#     and failed, and the pods and containers doctor said it removed.
#   * --dry-run lists the doctor commands it would run and changes nothing; it does not call the engine.
# It never deletes a run folder, a project or an image, and never starts, stops or restarts the engine.
# Exit: 0 done, 1 a doctor failed, 2 a refusal. For tests: YGG_LOCKS_FILE (default /proc/locks) and YGG_PROC_DIR
# (default /proc).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="$HOME/ygg-it" dry=0
keeps=() named=()
usage() { echo "usage: ygg-clean.sh [--dry-run] [--folder DIR] [--keep PROJECT]... [PROJECT...]" >&2; exit 2; }
fail() { echo "ygg-clean: $*" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --folder) [ $# -ge 2 ] || usage; dir="$2"; shift 2 ;;
    --keep) [ $# -ge 2 ] || usage; keeps+=("$2"); shift 2 ;;
    -*) usage ;;
    *) named+=("$1"); shift ;;
  esac
done
[ -d "$dir" ] || fail "no folder at $dir (--folder)"
dir="$(cd -P "$dir" && pwd -P)"
ygg="${YGG_CMD:-ygg}"
read -r -a ygg_arr <<<"$ygg"
command -v -- "${ygg_arr[0]}" >/dev/null 2>&1 || fail "no ygg on the path (YGG_CMD names how it runs)"
locks="${YGG_LOCKS_FILE:-/proc/locks}" proc="${YGG_PROC_DIR:-/proc}"
{ [ -f "$locks" ] && [ -r "$locks" ]; } || fail "cannot tell whether a run is live: $locks cannot be read; nothing was run"
{ [ -d "$proc" ] && [ -r "$proc" ]; } || fail "cannot tell whether a run is live: $proc cannot be read; nothing was run"
hidden="$dir/hidden-suites"

# lexical PATH: PATH made absolute with . and .. removed, from its text alone (no folder is entered or read).
lexical() {
  local p="$1" part
  local -a parts segs=()
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  IFS=/ read -r -a parts <<<"$p"
  for part in "${parts[@]}"; do
    case "$part" in
      '' | .) ;;
      ..) [ "${#segs[@]}" -eq 0 ] || unset 'segs[${#segs[@]}-1]' ;;
      *) segs+=("$part") ;;
    esac
  done
  local IFS=/
  echo "/${segs[*]}"
}
under_hidden() { case "$1/" in "$hidden"/*) return 0 ;; esac; return 1; }
# abs ARG: a name under DIR, else a folder, as an absolute path without links; fails when neither exists. A path
# under DIR/hidden-suites is refused from its text before it is entered, and again once its links are resolved.
abs() {
  local c p
  local -a cands=("$dir/$1" "$1")
  case "$1" in /*) cands=("$1") ;; esac
  for c in "${cands[@]}"; do
    if under_hidden "$(lexical "$c")"; then fail "$1 is under $hidden, which this script never enters"; fi
  done
  for c in "${cands[@]}"; do
    [ -d "$c" ] || continue
    p="$(cd -P "$c" && pwd -P)"
    if under_hidden "$p"; then fail "$1 is under $hidden, which this script never enters"; fi
    echo "$p"; return 0
  done
  return 1
}
# held LOCKFILE: true when the locks file has a FLOCK line for its device and inode (major:minor in hex, then the
# inode), the id odin's lock.Held computes. A locks file that cannot be read is a refusal, never "not held".
held() {
  local f="$1" d ino maj min id r=0
  [ -e "$f" ] || return 1
  read -r d ino < <(stat -c '%d %i' -- "$f")
  maj=$(( ((d >> 8) & 0xfff) | ((d >> 32) & ~0xfff) ))
  min=$(( (d & 0xff) | ((d >> 12) & ~0xff) ))
  printf -v id '%02x:%02x:%d' "$maj" "$min" "$ino"
  awk -v id="$id" '$2 == "FLOCK" && $6 == id { found = 1 } END { exit found ? 0 : 1 }' "$locks" || r=$?
  case "$r" in
    0) return 0 ;;
    1) return 1 ;;
    *) fail "cannot tell whether a run is live: $locks could not be read (awk exit $r); nothing more was run" ;;
  esac
}
# opened: the files the processes have open, one "PID TARGET" line each, from the PROC/PID/fd links. It is read
# again for each project, so it is current when that project's doctor is decided. A process this user cannot read
# is not listed; ygg runs as this user.
opened() {
  find "$proc"/[0-9]*/fd -mindepth 1 -maxdepth 1 -type l -printf '%h %l\n' 2>/dev/null |
    awk -v n="${#proc}" '{ h = $1; pid = substr(h, n + 2); sub(/\/fd$/, "", pid); t = substr($0, length(h) + 2)
      if (pid ~ /^[0-9]+$/ && t ~ /^\//) print pid, t }' || true
}
# open_by LOCKFILE: print the PID of a process that has LOCKFILE open, from $open_now; fails when none has.
open_by() {
  local f
  [ -e "$1" ] || return 1
  f="$(readlink -f -- "$1")"
  awk -v f="$f" 'substr($0, index($0, " ") + 1) == f { print $1; found = 1; exit } END { exit !found }' <<<"$open_now"
}

# The projects. The folders under DIR are walked by name, so a folder that is skipped is never listed.
projects=()
if [ "${#named[@]}" -gt 0 ]; then
  for n in "${named[@]}"; do
    p="$(abs "$n")" || { r=$?; [ "$r" -ne 2 ] || exit 2; fail "no folder $dir/$n (nor $n)"; }
    [ -d "$p/.factory/runs" ] || fail "$p holds no .factory/runs, so it is not a project"
    projects+=("$p")
  done
else
  [ ! -d "$dir/.factory/runs" ] || projects+=("$dir")
  for top in "$dir"/*/; do
    top="${top%/}"
    case "${top##*/}" in hidden-suites | dc | '*') continue ;; esac
    [ ! -d "$top/.factory/runs" ] || projects+=("$top")
    for sub in "$top"/*/; do
      sub="${sub%/}"
      [ ! -d "$sub/.factory/runs" ] || projects+=("$sub")
    done
  done
fi
keep_abs=()
for k in "${keeps[@]}"; do
  ka="$(abs "$k")" || { r=$?; [ "$r" -ne 2 ] || exit 2; fail "no folder $dir/$k (nor $k) to keep"; }
  keep_abs+=("$ka")
done

# The engine environment: once, for the real clean. A dry run does not call the engine.
if [ "$dry" -eq 0 ] && [ "${YGG_ENGINE_CHECK:-1}" = 1 ]; then
  engine_env="$("$HERE/ygg-engine.sh" env --folder "$dir")" || exit 2
  eval "$engine_env"
fi

# config_of PROJECT: print the config a doctor of that project should read, or fail.
config_of() {
  local p="$1" i c
  local -a rs=("$p"/.factory/runs/*/) # run ids sort by time, so the last is the newest
  for ((i = ${#rs[@]} - 1; i >= 0; i--)); do
    [ -f "${rs[i]}run.json" ] || continue
    c="$(sed -n 's/^.*"config_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/p' "${rs[i]}run.json" | head -n 1 || true)"
    if [ -n "$c" ] && [ -f "$c" ]; then echo "$c"; return 0; fi
  done
  for c in "$p/factory.yaml" "$(dirname "$p")/factory.yaml"; do
    if [ -f "$c" ]; then echo "$c"; return 0; fi
  done
  return 1
}

cleaned=() kept=() skipped=() failed=() removed=() rc=0
for p in "${projects[@]}"; do
  is_kept=0
  for k in "${keep_abs[@]}"; do
    case "$p" in "$k" | "$k"/*) is_kept=1 ;; esac
  done
  if [ "$is_kept" -eq 1 ]; then kept+=("$p"); echo "ygg-clean: keeping $p"; continue; fi
  open_now="$(opened)"
  if held "$p/.factory/locks/runs.lock"; then
    skipped+=("$p: a ygg process holds the project's runs lock"); echo "ygg-clean: skipping $p: a ygg process holds its runs lock"; continue
  fi
  if pid="$(open_by "$p/.factory/locks/runs.lock")"; then
    skipped+=("$p: a ygg process ($pid) has the project's runs lock open"); echo "ygg-clean: skipping $p: process $pid has its runs lock open"; continue
  fi
  live=""
  for r in "$p"/.factory/runs/*/; do
    [ -d "$r" ] || continue
    if held "${r}lock"; then live="run $(basename "$r") is live (a process holds its lock)"; break; fi
    if pid="$(open_by "${r}lock")"; then live="run $(basename "$r") is live (process $pid has its lock open)"; break; fi
  done
  if [ -n "$live" ]; then
    skipped+=("$p: $live"); echo "ygg-clean: skipping $p: $live"; continue
  fi
  if ! conf="$(config_of "$p")"; then
    skipped+=("$p: no config found (no config_path in a run.json, no factory.yaml in or beside the project)")
    echo "ygg-clean: skipping $p: no config found"; continue
  fi
  if [ "$dry" -eq 1 ]; then
    echo "ygg-clean: would run: $ygg doctor --project $p --config $conf"; cleaned+=("$p (dry run)"); continue
  fi
  echo "ygg-clean: ygg doctor on $p"
  code=0
  out="$("${ygg_arr[@]}" doctor --project "$p" --config "$conf" 2>&1)" || code=$?
  printf '%s\n' "$out"
  # doctor says "WARN  pods: run ID left the empty pod NAME (STATE); removed it", and the same of a container.
  while IFS= read -r line; do removed+=("$p: $line"); done < <(printf '%s\n' "$out" | sed -n 's/^WARN[[:space:]]*[a-z]*: \(.*; removed it\)$/\1/p')
  if [ "$code" -ne 0 ]; then failed+=("$p (ygg doctor exit $code)"); rc=1; else cleaned+=("$p"); fi
done

echo "ygg-clean: summary$([ "$dry" -eq 1 ] && echo ' (dry run: nothing was changed)')"
for x in "${cleaned[@]}"; do echo "  cleaned: $x"; done
for x in "${kept[@]}"; do echo "  kept: $x"; done
for x in "${skipped[@]}"; do echo "  skipped: $x"; done
for x in "${failed[@]}"; do echo "  failed: $x"; done
if [ "${#removed[@]}" -gt 0 ]; then
  echo "  pods and containers doctor removed:"
  for x in "${removed[@]}"; do echo "    $x"; done
elif [ "$dry" -eq 0 ]; then
  echo "  pods and containers doctor removed: none reported"
fi
exit "$rc"

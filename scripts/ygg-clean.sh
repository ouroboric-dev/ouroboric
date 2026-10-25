#!/usr/bin/env bash
# Clean up after runs that have ended: `ygg doctor` on each project, which removes the empty pods and the
# leftover containers of that project's runs.
#   ygg-clean.sh [--dry-run] [--folder DIR] [--keep PROJECT]... [PROJECT...]
# The projects are the PROJECTs named, or every folder that holds .factory/runs at DIR, DIR/NAME or DIR/NAME/SUB
# (default DIR $HOME/ygg-it), so DIR/smoke-real-TIME/project and DIR/proof-NAME-TIME/project. DIR/hidden-suites and
# DIR/dc are never entered. A PROJECT (and a --keep) is a folder, or a name under DIR. --keep P also keeps every
# project inside the folder P, so `--keep DIR/proof-r1-X` keeps that proof run's project.
#   * A project with a run whose lock a live process holds, or whose runs lock a live ygg holds, is skipped, and the
#     summary says which. The check reads /proc/locks as odin's lock.Held does: it never takes a lock and never
#     signals a process.
#   * The config is the one a run recorded (config_path in its run.json, newest run first), else PROJECT/factory.yaml
#     or factory.yaml beside the project. A project with no config is skipped with a message.
#   * It runs `ygg doctor --project P --config C` (YGG_CMD, default ygg), with the engine environment of
#     ygg-engine.sh (YGG_ENGINE_CHECK=0 skips it). The summary lists the projects cleaned, kept, skipped (and why)
#     and failed, and the pods and containers doctor said it removed.
#   * --dry-run lists the doctor commands it would run and changes nothing; it does not call the engine.
# It never deletes a run folder, a project or an image, and never starts, stops or restarts the engine.
# Exit: 0 done, 1 a doctor failed, 2 a refusal. For tests: YGG_LOCKS_FILE (default /proc/locks).
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
dir="$(cd "$dir" && pwd)"
ygg="${YGG_CMD:-ygg}"
read -r -a ygg_arr <<<"$ygg"
command -v -- "${ygg_arr[0]}" >/dev/null 2>&1 || fail "no ygg on the path (YGG_CMD names how it runs)"
locks="${YGG_LOCKS_FILE:-/proc/locks}"

# abs ARG: a folder, or a name under DIR, as an absolute path; fails when neither exists.
abs() {
  if [ -d "$1" ]; then (cd "$1" && pwd)
  elif [ -d "$dir/$1" ]; then (cd "$dir/$1" && pwd)
  else return 1; fi
}
# held LOCKFILE: true when the locks file has a FLOCK line for its device and inode (major:minor in hex, then the
# inode), the id odin's lock.Held computes.
held() {
  local f="$1" d ino maj min id
  [ -e "$f" ] || return 1
  read -r d ino < <(stat -c '%d %i' -- "$f")
  maj=$(( ((d >> 8) & 0xfff) | ((d >> 32) & ~0xfff) ))
  min=$(( (d & 0xff) | ((d >> 12) & ~0xff) ))
  printf -v id '%02x:%02x:%d' "$maj" "$min" "$ino"
  awk -v id="$id" '$2 == "FLOCK" && $6 == id { found = 1 } END { exit !found }' "$locks" 2>/dev/null
}

# The projects. The folders under DIR are walked by name, so a folder that is skipped is never listed.
projects=()
if [ "${#named[@]}" -gt 0 ]; then
  for n in "${named[@]}"; do
    p="$(abs "$n")" || fail "no folder $n (nor $dir/$n)"
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
  ka="$(abs "$k")" || fail "no folder $k (nor $dir/$k) to keep"
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
  if held "$p/.factory/locks/runs.lock"; then
    skipped+=("$p: a ygg process holds the project's runs lock"); echo "ygg-clean: skipping $p: a ygg process holds its runs lock"; continue
  fi
  live=""
  for r in "$p"/.factory/runs/*/; do
    [ -d "$r" ] || continue
    if held "${r}lock"; then live="$(basename "$r")"; break; fi
  done
  if [ -n "$live" ]; then
    skipped+=("$p: run $live is live (a process holds its lock)"); echo "ygg-clean: skipping $p: run $live is live"; continue
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

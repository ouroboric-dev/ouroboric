#!/usr/bin/env bash
# Build `ygg` from the umbrella's checkouts, with its go.work, and prove that the shell will run what was built.
#   ygg-build.sh [--yggdrasil DIR] [--out FILE] [--allow-behind] [--force]
# DIR is the umbrella (default: the yggdrasil folder beside this repo). It must hold go.work and odin.
#   1. For each module that DIR/go.work uses: a tree with uncommitted changes is refused, and so is a checkout
#      behind its origin/main (unless --allow-behind). Nothing is fetched: the comparison is with the local
#      origin/main ref, so `git -C MODULE pull` (or fetch) first. Each module and its short commit are printed.
#   2. The output OUT is --out FILE, else the ygg that is first on PATH, else $(go env GOPATH)/bin/ygg. An OUT that
#      exists must be a regular file (never a folder; a link only with --force) and a Go binary (`go version -m`);
#      a file that is not one is overwritten only with --force. The refusal names OUT.
#   3. `cd DIR/odin && go build -o OUT ./cmd/ygg` with GOWORK=DIR/go.work, to a temporary file that replaces OUT.
#      odin's internal/version reads the build info and takes no link-time stamp, so the facts go to OUT.build.txt:
#      odin and every module of go.work with its commit, and the SHA-256 of OUT (see ygg-build-facts.sh). The smoke
#      scripts read it to refuse a stale ygg.
#   4. `command -v ygg` must resolve to OUT, or this is an error naming both paths (fix PATH or pass --out). Then it
#      prints OUT, its time and the commits.
# It never writes to DIR, never starts the engine and never uses the network. Exit 0 built, 2 a refusal.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=ygg-build-facts.sh
. "$HERE/ygg-build-facts.sh"
ygg_dir="$HERE/../../yggdrasil" out="" allow_behind=0 force=0
usage() { echo "usage: ygg-build.sh [--yggdrasil DIR] [--out FILE] [--allow-behind] [--force]" >&2; exit 2; }
fail() { echo "ygg-build: $*" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --yggdrasil) [ $# -ge 2 ] || usage; ygg_dir="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; out="$2"; shift 2 ;;
    --allow-behind) allow_behind=1; shift ;;
    --force) force=1; shift ;;
    *) usage ;;
  esac
done
for tool in git go sha256sum; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"; done
[ -d "$ygg_dir" ] || fail "no umbrella folder at $ygg_dir (--yggdrasil)"
ygg_dir="$(cd "$ygg_dir" && pwd)"
[ -f "$ygg_dir/go.work" ] || fail "$ygg_dir/go.work is missing"
[ -d "$ygg_dir/odin" ] || fail "$ygg_dir/odin is missing"

# The modules: the paths of go.work's `use` lines, both `use ./x` and the block form.
mapfile -t modules < <(awk '
  /^use[[:space:]]*\(/ { inblock = 1; next }
  inblock && /^\)/ { inblock = 0; next }
  inblock { sub(/\/\/.*/, ""); gsub(/[[:space:]]/, ""); if ($0 != "") print; next }
  /^use[[:space:]]+[^(]/ { sub(/^use[[:space:]]+/, ""); sub(/\/\/.*/, ""); gsub(/[[:space:]]/, ""); print }
' "$ygg_dir/go.work")
[ "${#modules[@]}" -gt 0 ] || fail "$ygg_dir/go.work uses no module"
printf '%s\n' "${modules[@]}" | grep -q -x -F ./odin || fail "$ygg_dir/go.work does not use ./odin"

# 1. The inputs. All problems are listed before the script stops.
problems=0
facts=()
for m in "${modules[@]}"; do
  path="$ygg_dir/${m#./}" name="$(basename "$m")"
  if ! sha="$(git -C "$path" rev-parse --short=12 HEAD 2>/dev/null)"; then
    echo "ygg-build: $name: $path is not a git checkout" >&2; problems=1; continue
  fi
  echo "ygg-build: $name $sha"
  facts+=("$name: $sha")
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    echo "ygg-build: $name has uncommitted changes; commit or stash them in $path" >&2; problems=1
  fi
  if ! git -C "$path" rev-parse --verify -q origin/main >/dev/null 2>&1; then
    echo "ygg-build: $name has no origin/main ref to compare with; run: git -C $path fetch origin" >&2; problems=1
  else
    behind="$(git -C "$path" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
    if [ "$behind" -gt 0 ] && [ "$allow_behind" -eq 0 ]; then
      echo "ygg-build: $name is $behind commit(s) behind origin/main; update it: git -C $path pull --ff-only (or pass --allow-behind)" >&2; problems=1
    fi
  fi
done
[ "$problems" -eq 0 ] || fail "the inputs are not fit to build from; nothing was built"

# 2. The output, and what may be overwritten there.
if [ -z "$out" ]; then
  if first="$(command -v ygg 2>/dev/null)" && [ -n "$first" ]; then out="$first"
  else
    gopath="$(go env GOPATH)"
    out="${gopath%%:*}/bin/ygg"
  fi
fi
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
if [ -L "$out" ]; then
  [ "$force" -eq 1 ] || fail "$out is not a regular file but a link; nothing was built. Pass --out with the file it points to, or --force to replace the link"
elif [ -e "$out" ]; then
  [ -f "$out" ] || fail "$out is not a regular file; nothing was built (pass another --out)"
  if ! go version -m "$out" >/dev/null 2>&1 && [ "$force" -eq 0 ]; then
    fail "$out is not a Go binary (go version -m cannot read it); nothing was built. Pass --force to overwrite it"
  fi
fi
mkdir -p "$(dirname "$out")"

# 3. The build, to a temporary file in the same folder, so a running ygg is not overwritten in place.
tmp="$out.new.$$" tmp_facts="$out.build.txt.new.$$"
trap 'rm -f -- "$tmp" "$tmp_facts"' EXIT
(cd "$ygg_dir/odin" && GOWORK="$ygg_dir/go.work" go build -o "$tmp" ./cmd/ygg) || fail "go build of ygg failed in $ygg_dir/odin; $out is as it was"
[ -f "$tmp" ] || fail "go build wrote no $tmp; $out is as it was"
{
  echo "format: 1"
  echo "built: $(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "umbrella: $ygg_dir"
  for line in "${facts[@]}"; do echo "$line"; done
  echo "sha256: $(sha256sum "$tmp" | cut -d' ' -f1)"
} >"$tmp_facts"
mv -f -- "$tmp" "$out"
mv -f -- "$tmp_facts" "$out.build.txt"

# 4. The proof that the shell runs it.
on_path="$(command -v ygg 2>/dev/null || true)"
if [ -z "$on_path" ] || [ "$(readlink -f -- "$on_path")" != "$(readlink -f -- "$out")" ]; then
  fail "built $out, but \`command -v ygg\` resolves to ${on_path:-nothing}; put $(dirname "$out") first on PATH, or build to that ygg with --out ${on_path:-FILE}"
fi
echo "ygg-build: built $out ($(date -r "$out" '+%Y-%m-%d %H:%M:%S')); \`command -v ygg\` resolves to it"
echo "ygg-build: the facts are in $out.build.txt; the commits:"
for line in "${facts[@]}"; do echo "ygg-build:   ${line/: / }"; done

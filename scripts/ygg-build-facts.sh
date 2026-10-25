#!/usr/bin/env bash
# Sourced by ygg-build.sh, ygg-smoke-real.sh and ygg-proof-run.sh: what a built `ygg` says about itself, and the
# stale-binary guard. odin's internal/version reads the commits from the Go build info and takes no link-time stamp,
# so ygg-build.sh writes the facts of a build to BINARY.build.txt, beside the binary, one `name: value` line each:
# format, built, umbrella, one line per module of go.work (odin among them) with its commit, and sha256, the SHA-256
# of the binary it wrote. The commits are `git rev-parse --short=12 HEAD`, the width odin's version uses.
#   ygg_facts_get BINARY NAME        print the value of NAME in BINARY.build.txt; fail when there is no such file or line
#   ygg_stale_check BINARY ODIN      sets ygg_stale_msg; returns 0 when BINARY is the file ygg-build.sh wrote and was
#                                    built from the HEAD of the odin checkout ODIN, 1 otherwise
#   ygg_guard PREFIX BINARY ODIN ANY DRY
#                                    the guard of the smoke scripts: prints one "PREFIX: ygg guard: ..." line and
#                                    returns 1 when the script must refuse. ANY=1 (--any-ygg) skips the check and says
#                                    so; DRY=1 (a dry run) prints the result and never refuses.
ygg_facts_get() {
  local f="$1.build.txt"
  [ -f "$f" ] || return 1
  sed -n "s/^$2:[[:space:]]*//p" "$f" | head -n 1 | grep .
}

# shellcheck disable=SC2034 # ygg_stale_msg is read by the sourcing script
ygg_stale_check() {
  local bin="$1" odin="$2" built head sum want
  if ! built="$(ygg_facts_get "$bin" odin)"; then
    ygg_stale_msg="the ygg at $bin has no build facts ($bin.build.txt); run scripts/ygg-build.sh"
    return 1
  fi
  want="$(ygg_facts_get "$bin" sha256 || true)"
  sum="$(sha256sum "$bin" 2>/dev/null | cut -d' ' -f1)"
  if [ -z "$want" ] || [ "$sum" != "$want" ]; then
    ygg_stale_msg="the ygg at $bin is not the binary ygg-build.sh wrote (its SHA-256 is not the one in $bin.build.txt); run scripts/ygg-build.sh"
    return 1
  fi
  if ! head="$(git -C "$odin" rev-parse --short=12 HEAD 2>/dev/null)"; then
    ygg_stale_msg="the odin checkout $odin has no readable HEAD to compare the ygg at $bin with; run scripts/ygg-build.sh"
    return 1
  fi
  if [ "$built" != "$head" ]; then
    ygg_stale_msg="the ygg at $bin was built from odin $built, but the checkout $odin is at $head; run scripts/ygg-build.sh"
    return 1
  fi
  ygg_stale_msg="the ygg at $bin was built from odin $built, the HEAD of $odin"
  return 0
}

ygg_guard() {
  local prefix="$1" bin="$2" odin="$3" any="$4" dry="$5"
  if [ "$any" = 1 ]; then
    echo "$prefix: ygg guard: skipped (--any-ygg): $bin is used without checking which odin it was built from"
    return 0
  fi
  if ygg_stale_check "$bin" "$odin"; then
    echo "$prefix: ygg guard: ok: $ygg_stale_msg"
    return 0
  fi
  if [ "$dry" = 1 ]; then
    echo "$prefix: ygg guard: STALE: $ygg_stale_msg (a dry run: not refused)"
    return 0
  fi
  echo "$prefix: ygg guard: STALE: $ygg_stale_msg (or pass --any-ygg to use it anyway)" >&2
  return 1
}

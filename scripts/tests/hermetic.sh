#!/usr/bin/env bash
# Sourced first by the tests of the scripts that could reach the machine's own ygg, go or container engine
# (ygg-build, ygg-clean, ygg-smoke-real, ygg-proof-run). An earlier test kept the real PATH behind its fakes, so
# `command -v ygg` found the real ~/go/bin/ygg and a fake `go build -o` wrote over it. These tests therefore run
# whole under env -i, and every script they start inherits that environment and nothing else.
#   hermetic_enter "$@"   The first time: makes the test's folder T (mktemp -d) with T/home, T/gopath and T/bin, links
#                         the tools named in HERMETIC_TOOLS from the caller's PATH into T/bin (never ygg, go or an
#                         engine), puts fakes of podman and docker there that log to T/engine.calls and fail, records
#                         the stat of every ygg on the caller's PATH, of ~/go/bin/ygg and ~/.local/bin/ygg (and their
#                         .build.txt), then runs the test again under
#                         env -i HOME=T/home PATH=T/bin:/usr/bin:/bin GOPATH=T/gopath HERMETIC_T=T, with VERBOSE and
#                         the variables named in HERMETIC_PASS (read-only inputs, such as YGG_REAL_ODIN) when set.
#                         The second time it only sets T. The test then adds the variables it needs itself.
#   hermetic_done         The last check of a test: those files are as they were, and no engine was called. It prints
#                         ok or FAIL and sets fail=1 on a FAIL.
# A caller's PATH entry for a case is a folder under T, then $BASEPATH (T/bin:/usr/bin:/bin); hermetic_path_ok says so.

hermetic_stat() { # WATCHLIST: one line per file: its path, then its size, mtime and inode, or "missing"
  local f
  while IFS= read -r f; do
    if [ -e "$f" ] || [ -L "$f" ]; then printf '%s %s\n' "$f" "$(stat -c '%s %Y %i' -- "$f")"
    else printf '%s missing\n' "$f"; fi
  done <"$1"
}

hermetic_enter() {
  if [ -n "${HERMETIC_T:-}" ]; then
    T="$HERMETIC_T"
    BASEPATH="$T/bin:/usr/bin:/bin"
    # The guard of the guard: with a ygg or go of the machine in sight, or HOME or GOPATH outside T, nothing runs.
    if [ "$PATH" != "$BASEPATH" ] || command -v ygg >/dev/null || command -v go >/dev/null ||
      [ "${HOME#"$T"/}" = "$HOME" ] || [ "${GOPATH#"$T"/}" = "$GOPATH" ]; then
      echo "FAIL the test is not hermetic (PATH $PATH, HOME $HOME, GOPATH $GOPATH); nothing was run"
      exit 3
    fi
    echo "ok   the test runs under env -i, with PATH, HOME and GOPATH in its own folder"
    return 0
  fi
  local t home tool f e
  t="$(mktemp -d)"
  home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
  [ -n "$home" ] || home="$HOME"
  mkdir -p "$t/bin" "$t/home" "$t/gopath"
  for tool in ${HERMETIC_TOOLS:-}; do
    case "$tool" in ygg | go | podman | docker) echo "hermetic: $tool is never linked into a test's PATH" >&2; rm -rf -- "$t"; exit 1 ;; esac
    f="$(command -v "$tool")" || { echo "hermetic: $tool is not installed" >&2; rm -rf -- "$t"; exit 1; }
    ln -s "$f" "$t/bin/$tool"
  done
  for e in podman docker; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/engine.calls"\nexit 97\n' "$e" "$t" >"$t/bin/$e"
    chmod +x "$t/bin/$e"
  done
  { type -ap ygg || true; echo "$home/go/bin/ygg"; echo "$home/.local/bin/ygg"; } | sort -u |
    while IFS= read -r f; do echo "$f"; echo "$f.build.txt"; done >"$t/hermetic.watch"
  hermetic_stat "$t/hermetic.watch" >"$t/hermetic.before"
  local -a keep=()
  for e in VERBOSE ${HERMETIC_PASS:-}; do
    case "$e" in PATH | HOME | GOPATH | GOWORK | YGG_CMD) echo "hermetic: $e is never passed" >&2; rm -rf -- "$t"; exit 1 ;; esac
    [ -z "${!e+x}" ] || keep+=("$e=${!e}")
  done
  exec env -i HOME="$t/home" PATH="$t/bin:/usr/bin:/bin" GOPATH="$t/gopath" HERMETIC_T="$t" "${keep[@]}" "$BASH" "$0" "$@"
}

hermetic_path_ok() { # PATH: true when each entry is a folder under T, or is /usr/bin or /bin
  local p
  local -a parts
  IFS=: read -r -a parts <<<"$1"
  for p in "${parts[@]}"; do
    case "$p" in "$T"/* | /usr/bin | /bin) ;; *) return 1 ;; esac
  done
}

# shellcheck disable=SC2034 # fail is the sourcing test's
hermetic_done() {
  if [ "$(hermetic_stat "$T/hermetic.watch")" = "$(cat "$T/hermetic.before")" ]; then
    echo "ok   nothing outside the test's folder changed (the machine's ygg binaries are as they were)"
  else
    echo "FAIL a file outside the test's folder changed:"
    diff <(cat "$T/hermetic.before") <(hermetic_stat "$T/hermetic.watch") | sed 's/^/     | /'
    fail=1
  fi
  if [ -s "$T/engine.calls" ]; then
    echo "FAIL an engine was called:"; sed 's/^/     | /' "$T/engine.calls"; fail=1
  else
    echo "ok   no engine was called"
  fi
}

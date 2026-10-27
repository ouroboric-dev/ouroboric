#!/usr/bin/env bash
# Tests for ygg-build.sh and the stale-binary check of ygg-build-facts.sh.   scripts/tests/ygg-build.test.sh
# A made-up umbrella (git repos with a local origin/main ref, a go.work) and a fake `go` that logs its calls and
# writes a fake ygg: no network, no real build, no engine. The whole test runs under env -i (hermetic.sh): its PATH is
# folders of its own and /usr/bin:/bin, so the machine's ygg and go are never found.
# shellcheck disable=SC2329 # check calls has and hasnt by name
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=hermetic.sh
. "$HERE/hermetic.sh"
HERMETIC_TOOLS="git" hermetic_enter "$@"
S="$HERE/.."
trap 'rm -rf -- "$T"' EXIT
fail=0
check() {
  local d="$1"; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; [ -z "${VERBOSE:-}" ] || sed 's/^/     | /' "$T/out"; fi
}
# run CMD...: a case. Its PATH must stay in T (and /usr/bin:/bin), or the test stops before anything runs.
run() {
  hermetic_path_ok "$PATH" || { echo "FAIL the test's PATH leaves its folder: $PATH"; exit 3; }
  "$@" >"$T/out" 2>&1; rc=$?
}
has() { grep -q -F -- "$1" "$T/out"; }
hasnt() { ! grep -q -F -- "$1" "$T/out"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
G=(git -c user.name=t -c user.email=t@example.invalid)

# The umbrella: go.work with a block, odin and gungnir, each a repo whose origin/main is its first commit.
U="$T/ygg"; mkdir -p "$U"
printf 'go 1.26\n\nuse (\n\t./gungnir\n\t./odin // the CLI\n)\n' >"$U/go.work"
for m in odin gungnir; do
  mkdir -p "$U/$m"; git -C "$U/$m" init -q -b main
  printf 'x\n' >"$U/$m/f.txt"; git -C "$U/$m" add f.txt; "${G[@]}" -C "$U/$m" commit -q -m first
  git -C "$U/$m" update-ref refs/remotes/origin/main HEAD
done
sha() { git -C "$U/$1" rev-parse --short=12 HEAD; }
# advance_origin MODULE: origin/main moves one commit ahead of the checkout (the checkout is behind).
advance_origin() {
  git -C "$U/$1" checkout -q -b tmp; printf 'y\n' >>"$U/$1/f.txt"; "${G[@]}" -C "$U/$1" commit -q -am second
  git -C "$U/$1" update-ref refs/remotes/origin/main HEAD; git -C "$U/$1" checkout -q main; git -C "$U/$1" branch -q -D tmp
}

# A fake go: `go env GOPATH` (the test's GOPATH), `go version -m FILE` (a Go binary is a file with the fake's mark),
# and `go build -o OUT ./cmd/ygg`, which logs the folder and GOWORK and writes a fake ygg with the mark.
GB="$T/gobin"; mkdir -p "$GB" "$T/gopath/bin" "$T/pathbin"
cat >"$GB/go" <<'EOF2'
#!/usr/bin/env bash
echo "go $*" >>"$FAKE_LOG"
if [ "$1" = env ] && [ "$2" = GOPATH ]; then echo "$GOPATH"; exit 0; fi
if [ "$1" = version ] && [ "$2" = -m ]; then
  if grep -q -s 'fake go binary' "$3"; then printf '%s: go1.26\n\tpath\tgithub.com/ouroboric-dev/odin/cmd/ygg\n' "$3"; exit 0; fi
  echo "$3: could not read Go build info" >&2; exit 1
fi
if [ "$1" = build ] && [ "$2" = -o ]; then
  echo "built $3 $4 in $PWD GOWORK=$GOWORK" >>"$FAKE_LOG"
  [ -z "${FAKE_BUILD_FAIL:-}" ] || exit 1
  printf '#!/usr/bin/env bash\n# fake go binary %s\nexit 0\n' "$RANDOM$RANDOM" >"$3"; chmod +x "$3"; exit 0
fi
exit 1
EOF2
# A git that logs its calls before the real one, so a fetch would show.
printf '#!/bin/sh\necho "git $*" >>"%s/git.log"\nexec "%s/bin/git" "$@"\n' "$T" "$T" >"$GB/git"
chmod +x "$GB/go" "$GB/git"
export FAKE_LOG="$T/calls.log"
# old FILE: an older fake Go build at FILE. fresh: one first on PATH; fresh_none: no ygg anywhere.
old() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n# fake go binary old\necho old\n' >"$1"; chmod +x "$1"; }
fresh_none() { : >"$FAKE_LOG"; rm -rf "$T/pathbin/ygg" "$T/pathbin/ygg.build.txt" "$T/gopath/bin/ygg" "$T/gopath/bin/ygg.build.txt" "$T/elsewhere"; }
fresh() { fresh_none; old "$T/pathbin/ygg"; }
built() { grep -q '^built ' "$FAKE_LOG"; } # a go build ran


# --- the happy path: the ygg first on PATH is rebuilt in place
fresh
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
check "a clean umbrella builds, exit 0" test "$rc" -eq 0
check "it prints each module and its commit" bash -c "grep -q 'odin $(sha odin)' '$T/out' && grep -q 'gungnir $(sha gungnir)' '$T/out'"
check "the output is the ygg first on PATH" grep -q -F "built $T/pathbin/ygg.new." "$FAKE_LOG"
check "it builds ./cmd/ygg in odin, with the umbrella's go.work" grep -q -F "./cmd/ygg in $U/odin GOWORK=$U/go.work" "$FAKE_LOG"
check "it checks that the old file is a Go binary before it writes" grep -q -F "go version -m $T/pathbin/ygg" "$FAKE_LOG"
check "the built file replaced the old one" bash -c "! grep -q old '$T/pathbin/ygg'"
check "the facts file names odin's commit" grep -q -x "odin: $(sha odin)" "$T/pathbin/ygg.build.txt"
check "the facts file names every module of go.work" grep -q -x "gungnir: $(sha gungnir)" "$T/pathbin/ygg.build.txt"
check "the facts file has the SHA-256 of the binary" grep -q -x "sha256: $(sha256sum "$T/pathbin/ygg" | cut -d' ' -f1)" "$T/pathbin/ygg.build.txt"
check "it prints the output path and its time" bash -c "grep -q -F 'built $T/pathbin/ygg (' '$T/out' && grep -q -E 'built .*\\([0-9]{4}-[0-9]{2}-[0-9]{2} ' '$T/out'"
check "it prints the commits at the end" bash -c "tail -n 3 '$T/out' | grep -q 'odin $(sha odin)'"
check "no temporary file is left" bash -c "! ls '$T/pathbin' | grep -q '\\.new\\.'"

# --- no ygg on PATH: GOPATH/bin, which is then not on PATH: the mismatch error
fresh_none
PATH="$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
check "with no ygg on PATH the output is GOPATH/bin/ygg" test -x "$T/gopath/bin/ygg"
check "and a ygg that PATH does not resolve is an error (exit 2)" test "$rc" -eq 2
check "the error names the built path and says nothing resolves" has "built $T/gopath/bin/ygg, but \`command -v ygg\` resolves to nothing"
check "the error says how to fix PATH" has "put $T/gopath/bin first on PATH"
fresh_none
PATH="$T/gopath/bin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
check "with GOPATH/bin on PATH the same build passes" test "$rc" -eq 0

# --- --out, and the PATH mismatch with another ygg first
fresh
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --out "$T/elsewhere/ygg"
check "--out builds there" test -x "$T/elsewhere/ygg"
check "the ygg first on PATH is not touched" grep -q old "$T/pathbin/ygg"
check "a ygg earlier on PATH than --out is a hard error" test "$rc" -eq 2
check "the error names both paths" bash -c "grep -q -F '$T/elsewhere/ygg' '$T/out' && grep -q -F 'resolves to $T/pathbin/ygg' '$T/out'"

# --- --beside-path: a second ygg beside the one on PATH (B-214)
fresh
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --out "$T/elsewhere/ygg" --beside-path
check "--beside-path builds OUT while another ygg is first on PATH, exit 0" bash -c "[ $rc -eq 0 ] && [ -x '$T/elsewhere/ygg' ]"
check "the ygg first on PATH is not touched" grep -q old "$T/pathbin/ygg"
check "it writes the facts beside OUT" grep -q "^odin: $(sha odin)\$" "$T/elsewhere/ygg.build.txt"
check "it prints the YGG_CMD line" has "YGG_CMD=$T/elsewhere/ygg"
check "it notes that PATH resolves elsewhere" has "resolves to $T/pathbin/ygg"
fresh_none
PATH="$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --out "$T/elsewhere/ygg" --beside-path
check "--beside-path with no ygg on PATH builds too, and prints the YGG_CMD line" bash -c "[ $rc -eq 0 ] && grep -q -F 'YGG_CMD=$T/elsewhere/ygg' '$T/out'"
fresh
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --beside-path
check "--beside-path without --out is a usage error (exit 2), and builds nothing" bash -c "[ $rc -eq 2 ] && grep -q usage '$T/out' && ! grep -q '^built ' '$FAKE_LOG'"
fresh
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --out "$T/pathbin/ygg" --beside-path
check "--beside-path with OUT the ygg on PATH passes and prints no YGG_CMD line" bash -c "[ $rc -eq 0 ] && ! grep -q 'YGG_CMD=' '$T/out'"

# --- an OUT that is not a Go binary, or not a file: refused, and named; --force overwrites a file
fresh; printf '#!/bin/sh\necho a wrapper\n' >"$T/pathbin/ygg"
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
check "an OUT that is not a Go binary is refused (exit 2)" test "$rc" -eq 2
check "the refusal names OUT and says --force" bash -c "grep -q -F '$T/pathbin/ygg is not a Go binary' '$T/out' && grep -q -F -- '--force' '$T/out'"
check "nothing was built and OUT is as it was" bash -c "! grep -q '^built ' '$FAKE_LOG' && grep -q 'a wrapper' '$T/pathbin/ygg'"
: >"$FAKE_LOG"
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --force
check "with --force it is overwritten" bash -c "[ $rc -eq 0 ] && ! grep -q 'a wrapper' '$T/pathbin/ygg'"
fresh_none; mkdir -p "$T/elsewhere/ygg"
PATH="$T/elsewhere:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --out "$T/elsewhere/ygg" --force
check "an OUT that is a folder is refused, even with --force" bash -c "[ $rc -eq 2 ] && grep -q -F '$T/elsewhere/ygg is not a regular file' '$T/out'"
check "and nothing was built into it" bash -c "! grep -q '^built ' '$FAKE_LOG' && [ -z \"\$(ls -A '$T/elsewhere/ygg')\" ]"
fresh_none; mkdir -p "$T/linkbin"; ln -s "$T/nowhere/ygg" "$T/linkbin/ygg"
PATH="$T/linkbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --out "$T/linkbin/ygg"
check "an --out link that points to nothing is refused" bash -c "[ $rc -eq 2 ] && grep -q -F '$T/linkbin/ygg is a link to $T/nowhere/ygg, which does not exist' '$T/out' && [ ! -e '$T/nowhere' ]"
rm -rf "$T/linkbin"; mkdir -p "$T/linkbin" "$T/real"; printf '#!/bin/sh\necho a wrapper\n' >"$T/real/ygg"; chmod +x "$T/real/ygg"
ln -s "$T/real/ygg" "$T/linkbin/ygg"
PATH="$T/linkbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
check "a link to a file that is not a Go binary is refused, naming the target" bash -c "[ $rc -eq 2 ] && grep -q -F '$T/real/ygg is not a Go binary' '$T/out' && grep -q 'a wrapper' '$T/real/ygg'"
rm -rf "$T/linkbin" "$T/real"

# --- a dirty module is refused, and nothing is built
fresh; printf 'dirty\n' >>"$U/gungnir/f.txt"
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
check "a dirty module is refused (exit 2)" test "$rc" -eq 2
check "the message names the module and how to fix it" has "gungnir has uncommitted changes; commit or stash them in $U/gungnir"
check "nothing was built" bash -c "! grep -q '^built ' '$FAKE_LOG'"
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --allow-behind
check "--allow-behind does not excuse a dirty tree" test "$rc" -eq 2
git -C "$U/gungnir" checkout -q f.txt

# --- a module behind origin/main
fresh; advance_origin odin
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
check "a module behind origin/main is refused" test "$rc" -eq 2
check "the message names the module and how many" has "odin is 1 commit(s) behind origin/main"
check "the message says how to update it" has "git -C $U/odin pull --ff-only"
check "nothing was built when behind" bash -c "! grep -q '^built ' '$FAKE_LOG'"
check "the script ran git, and nothing was fetched" bash -c "grep -q 'rev-list' '$T/git.log' && ! grep -q -E 'git (.* )?(fetch|pull|remote)' '$T/git.log'"
: >"$FAKE_LOG"
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --allow-behind
check "--allow-behind builds anyway" test "$rc" -eq 0
check "and the facts hold the checkout's commit, not origin's" grep -q -x "odin: $(sha odin)" "$T/pathbin/ygg.build.txt"
git -C "$U/odin" update-ref refs/remotes/origin/main HEAD

# --- no origin/main ref to compare with
fresh; git -C "$U/gungnir" update-ref -d refs/remotes/origin/main
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
check "a module with no origin/main is refused, with the fetch to run" bash -c "[ $rc -eq 2 ] && grep -q -F 'gungnir has no origin/main ref to compare with; run: git -C $U/gungnir fetch origin' '$T/out'"
git -C "$U/gungnir" update-ref refs/remotes/origin/main HEAD

# --- the build fails: an error, OUT as it was, no facts
fresh
FAKE_BUILD_FAIL=1 PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
check "a failed go build is an error" test "$rc" -eq 2
check "and leaves OUT as it was" grep -q old "$T/pathbin/ygg"
check "and leaves no facts file" test ! -e "$T/pathbin/ygg.build.txt"

# --- bad flags and a bad umbrella
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --out
check "a flag with no value is a usage error" bash -c "[ $rc -eq 2 ] && grep -q usage '$T/out'"
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --nope
check "an unknown flag is a usage error" test "$rc" -eq 2
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$T/none"
check "a missing umbrella is refused" bash -c "[ $rc -eq 2 ] && grep -q -F 'no umbrella folder at $T/none' '$T/out'"

# --- the stale check (the library the smoke scripts use)
SA="$(cd "$S" && pwd)" # the scripts folder, as the message names it
stale() { # BINARY ODIN: runs ygg_stale_check in a subshell and prints the message and the result
  # shellcheck source-path=SCRIPTDIR source=../ygg-build-facts.sh
  ( . "$S/ygg-build-facts.sh"; if ygg_stale_check "$1" "$2"; then echo "FRESH: $ygg_stale_msg"; else echo "STALE: $ygg_stale_msg"; fi )
}
fresh; PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
stale "$T/pathbin/ygg" "$U/odin" >"$T/out"
check "a binary built from odin's HEAD is fresh" has "FRESH: the ygg at $T/pathbin/ygg was built from odin $(sha odin)"
printf '# changed\n' >>"$T/pathbin/ygg"; stale "$T/pathbin/ygg" "$U/odin" >"$T/out"
check "a binary changed after its build (another go install) is stale" has "STALE: the ygg at $T/pathbin/ygg is not the binary ygg-build.sh wrote"
rm "$T/pathbin/ygg.build.txt"; stale "$T/pathbin/ygg" "$U/odin" >"$T/out"
check "a binary with no facts is stale" has "STALE: the ygg at $T/pathbin/ygg has no build facts"
check "the message gives the whole command to paste" has "; run: $SA/ygg-build.sh --yggdrasil $U"
printf 'format: 1\nodin: 000000000000\nsha256: %s\n' "$(sha256sum "$T/pathbin/ygg" | cut -d' ' -f1)" >"$T/pathbin/ygg.build.txt"
stale "$T/pathbin/ygg" "$U/odin" >"$T/out"
check "a binary from another commit is stale, with both commits" has "built from odin 000000000000, but the checkout $U/odin is at $(sha odin)"

# --- the guard (ygg_guard, as the smoke scripts call it): no ygg on PATH, and a ygg on PATH through a link
guard() { # ODIN ANY DRY [CMD]: runs ygg_guard with this test's PATH and prints its line and its result
  # shellcheck source-path=SCRIPTDIR source=../ygg-build-facts.sh
  ( . "$S/ygg-build-facts.sh"; if ygg_guard test "$1" "$2" "$3" "${4:-}"; then echo "PASS"; else echo "REFUSED"; fi ) 2>&1
}
fresh_none
PATH="$GB:$BASEPATH" guard "$U/odin" 0 0 >"$T/out"
check "with no ygg on PATH the guard says so" bash -c "grep -q -F 'test: ygg guard: STALE: no ygg is on PATH; run: $SA/ygg-build.sh --yggdrasil $U' '$T/out' && grep -q REFUSED '$T/out'"
check "and never says 'the ygg at  has'" hasnt "the ygg at  has"
# The link case end to end: a link on PATH, the guard refuses; the build writes the link's target; the guard passes.
mkdir -p "$T/linkbin"; old "$T/real/ygg"; ln -s "$T/real/ygg" "$T/linkbin/ygg"
PATH="$T/linkbin:$GB:$BASEPATH" guard "$U/odin" 0 0 >"$T/out"
check "link: the guard reads the facts beside the link's target, and refuses with none" bash -c "grep -q -F 'STALE: the ygg at $T/real/ygg has no build facts ($T/real/ygg.build.txt)' '$T/out' && grep -q REFUSED '$T/out'"
PATH="$T/linkbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U"
check "link: ygg-build.sh builds to the link's target" bash -c "[ $rc -eq 0 ] && grep -q -F 'built $T/real/ygg' '$T/out' && grep -q -F 'built $T/real/ygg.new.' '$FAKE_LOG'"
check "link: the link stays a link, and the facts are beside the target" bash -c "[ -L '$T/linkbin/ygg' ] && [ -f '$T/real/ygg.build.txt' ] && [ ! -e '$T/linkbin/ygg.build.txt' ] && ! grep -q old '$T/real/ygg'"
PATH="$T/linkbin:$GB:$BASEPATH" guard "$U/odin" 0 0 >"$T/out"
check "link: then the guard passes" bash -c "grep -q -F 'test: ygg guard: ok: the ygg at $T/real/ygg was built from odin $(sha odin)' '$T/out' && grep -q PASS '$T/out'"
rm -f "$T/real/ygg.build.txt"
PATH="$T/linkbin:$GB:$BASEPATH" guard "$U/odin" 0 1 >"$T/out"
check "a dry run prints STALE and passes" bash -c "grep -q 'STALE: .*(a dry run: not refused)' '$T/out' && grep -q PASS '$T/out'"
PATH="$T/linkbin:$GB:$BASEPATH" guard "$U/odin" 1 0 >"$T/out"
check "--any-ygg skips the check and passes" bash -c "grep -q -F 'test: ygg guard: skipped (--any-ygg)' '$T/out' && grep -q PASS '$T/out'"
rm -rf "$T/linkbin" "$T/real"

# The guard for a YGG_CMD (the fifth argument): one executable file is checked, anything else is used unchecked.
fresh_none; old "$T/second/ygg"; : >"$T/second/note"
PATH="$GB:$BASEPATH" guard "$U/odin" 0 0 "$T/second/ygg" >"$T/out"
check "CMD: a file with no facts is STALE and refused, though no ygg is on PATH" bash -c "grep -q -F 'test: ygg guard: STALE: the ygg at $T/second/ygg has no build facts' '$T/out' && grep -q REFUSED '$T/out'"
PATH="$GB:$BASEPATH" guard "$U/odin" 0 1 "$T/second/ygg" >"$T/out"
check "CMD: a dry run prints STALE and passes" bash -c "grep -q 'STALE: .*(a dry run: not refused)' '$T/out' && grep -q PASS '$T/out'"
PATH="$GB:$BASEPATH" guard "$U/odin" 1 0 "$T/second/ygg" >"$T/out"
check "CMD: --any-ygg skips the check and passes" bash -c "grep -q -F 'test: ygg guard: skipped (--any-ygg): $T/second/ygg' '$T/out' && grep -q PASS '$T/out'"
PATH="$T/pathbin:$GB:$BASEPATH" run "$S/ygg-build.sh" --yggdrasil "$U" --out "$T/second/ygg" --beside-path
PATH="$GB:$BASEPATH" guard "$U/odin" 0 0 "$T/second/ygg" >"$T/out"
check "CMD: after ygg-build.sh --beside-path the guard passes" bash -c "grep -q -F 'test: ygg guard: ok: the ygg at $T/second/ygg was built from odin $(sha odin)' '$T/out' && grep -q PASS '$T/out'"
PATH="$GB:$BASEPATH" guard "$U/odin" 0 0 "$T/second/ygg --extra" >"$T/out"
check "CMD: several words are used unchecked, with a line that says so" bash -c "grep -q -F 'test: ygg guard: YGG_CMD ($T/second/ygg --extra) is not one executable file: it is used without checking' '$T/out' && grep -q PASS '$T/out'"
PATH="$GB:$BASEPATH" guard "$U/odin" 0 0 "$T/second/none" >"$T/out"
check "CMD: a word that is no file is used unchecked too" bash -c "grep -q -F 'is not one executable file' '$T/out' && grep -q PASS '$T/out'"
PATH="$GB:$BASEPATH" guard "$U/odin" 0 0 "$T/second/note" >"$T/out"
check "CMD: a file that is not executable is used unchecked" bash -c "grep -q -F 'is not one executable file' '$T/out' && grep -q PASS '$T/out'"
rm -rf "$T/second"

hermetic_done
echo; [ "$fail" -eq 0 ] && echo "ygg-build.test.sh: all ok" || echo "ygg-build.test.sh: FAILURES"
exit "$fail"

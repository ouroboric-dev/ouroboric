#!/usr/bin/env bash
# Tests for add-ci.sh.   scripts/tests/add-ci.test.sh
# The last cases run the real pre-commit hooks through uvx (they need the network, Go and node the first time).
# The fake secret is made at run time, so this repo's own gitleaks hook never sees one.
# shellcheck disable=SC2329  # the case functions are called by check
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../add-ci.sh"
PIECES="$HERE/../templates/ci/pieces"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
files() { (cd "$1" && find . -type f -not -path './.git/*' | LC_ALL=C sort | tr '\n' ' '); }
empty() { [ -z "$(ls -A "$1")" ]; }
repos() { grep '^  - repo:' "$1/.pre-commit-config.yaml" | sed 's|.*/||' | tr '\n' ' '; }

mkdir "$T/dev"
"$S" --org ouroboric-dev "$T/dev"
check "ouroboric-dev: the three files" \
  [ "$(files "$T/dev")" = "./.github/workflows/lint.yml ./.markdownlint.yaml ./.pre-commit-config.yaml " ]
check "ouroboric-dev: gitleaks, reuse-tool, markdownlint-cli2, actionlint" \
  [ "$(repos "$T/dev")" = "gitleaks reuse-tool markdownlint-cli2 actionlint " ]
check "the config starts with repos:" [ "$(head -n1 "$T/dev/.pre-commit-config.yaml")" = "repos:" ]
check "lint.yml is the template" cmp -s "$HERE/../templates/ci/lint.yml" "$T/dev/.github/workflows/lint.yml"
check ".markdownlint.yaml is the piece's file" cmp -s "$PIECES/markdown.files/.markdownlint.yaml" "$T/dev/.markdownlint.yaml"

mkdir "$T/sh"
"$S" --org ouroboric-dev --ci shell "$T/sh"
check "--ci shell: gitleaks then shellcheck-py" [ "$(repos "$T/sh")" = "gitleaks shellcheck-py " ]
mkdir "$T/dup"
"$S" --org ouroboric-dev --ci gitleaks,gitleaks "$T/dup"
check "--ci gitleaks,gitleaks: one gitleaks" [ "$(repos "$T/dup")" = "gitleaks " ]
mkdir "$T/dup2"
"$S" --org ouroboric-dev --ci shell,reuse,shell "$T/dup2"
check "a repeated piece is kept once, in first-seen order" [ "$(repos "$T/dup2")" = "gitleaks shellcheck-py reuse-tool " ]

# Refusals: exit 2, nothing written.
mkdir "$T/bad1" "$T/bad2" "$T/bad3" "$T/bad4" "$T/bad5" "$T/bad6"
"$S" --org ouroboric-dev --ci nope "$T/bad1" 2>/dev/null; rc1=$?
"$S" --org ouroboric-dev --ci reuse,,markdown "$T/bad2" 2>/dev/null; rc2=$?
echo mine > "$T/bad3/.pre-commit-config.yaml"
"$S" --org ouroboric-dev "$T/bad3" 2>/dev/null; rc3=$?
case1() { [ "$rc1" = 2 ] && empty "$T/bad1"; }
case2() { [ "$rc2" = 2 ] && empty "$T/bad2"; }
case3() { [ "$rc3" = 2 ] && [ "$(files "$T/bad3")" = "./.pre-commit-config.yaml " ] && [ "$(cat "$T/bad3/.pre-commit-config.yaml")" = mine ]; }
check "an unknown piece: exit 2, nothing written" case1
check "an empty item: exit 2, nothing written" case2
check "an existing .pre-commit-config.yaml: exit 2, nothing else written" case3

# An existing lint.yml or piece file also blocks everything.
mkdir -p "$T/bad4/.github/workflows"
echo mine > "$T/bad4/.github/workflows/lint.yml"
"$S" --org ouroboric-dev "$T/bad4" 2>/dev/null; rc4=$?
case4() { [ "$rc4" = 2 ] && [ "$(files "$T/bad4")" = "./.github/workflows/lint.yml " ]; }
check "an existing lint.yml: exit 2, nothing else written" case4
echo mine > "$T/bad5/.markdownlint.yaml"
"$S" --org ouroboric-dev "$T/bad5" 2>/dev/null; rc5=$?
case5() { [ "$rc5" = 2 ] && [ "$(files "$T/bad5")" = "./.markdownlint.yaml " ]; }
check "an existing piece file: exit 2, nothing else written" case5
echo mine > "$T/bad6/.github"
"$S" --org ouroboric-dev "$T/bad6" 2>/dev/null; rc6=$?
case6() { [ "$rc6" = 2 ] && [ "$(files "$T/bad6")" = "./.github " ]; }
check "a file named .github: exit 2, nothing else written" case6
mkdir "$T/bad7"
"$S" --org ouroboric-dev --ci "" "$T/bad7" 2>/dev/null; rc7=$?
"$S" --org ouroboric-dev --ci "" --check 2>/dev/null; rc7c=$?
case7() { [ "$rc7$rc7c" = 22 ] && empty "$T/bad7"; }
check "--ci with an empty value: exit 2, nothing written" case7

# Fixture pieces that break the contract.
fx() { # fx <folder> <name> <text>: a fixture pieces folder with a good gitleaks and one piece
  mkdir -p "$T/$1"
  cp "$PIECES/gitleaks.yaml" "$T/$1/gitleaks.yaml"
  printf '%s\n' "$3" > "$T/$1/$2.yaml"
}
good='  - repo: https://example.com/a
    rev: v1.2.3
    hooks:
      - id: a'
fx two two "$good
  - repo: https://example.com/b
    rev: v1.2.3
    hooks:
      - id: b"
fx main main "  - repo: https://example.com/a
    rev: main
    hooks:
      - id: a"
fx tab tab "$good
	"
fx nohooks nohooks "  - repo: https://example.com/a
    rev: v1.2.3"
fx http http "  - repo: http://example.com/a
    rev: v1.2.3
    hooks:
      - id: a"
fx ok ok "$good"
for n in two main tab nohooks http; do
  mkdir "$T/out-$n"
  ADD_CI_PIECES="$T/$n" "$S" --org ouroboric-dev --ci "$n" "$T/out-$n" 2>"$T/err-$n"; eval "rc_$n=\$?"
done
rule() { local rc="rc_$1"; [ "${!rc}" = 2 ] && empty "$T/out-$1" && grep -q "$1" "$T/err-$1"; }
check "a piece with two repo: lines is refused, and named" rule two
check "a piece with rev: main is refused, and named" rule main
check "a piece with a tab is refused, and named" rule tab
check "a piece with no hooks: line is refused, and named" rule nohooks
check "a piece with a non-https repo is refused, and named" rule http
mkdir "$T/out-ok"
ADD_CI_PIECES="$T/ok" "$S" --org ouroboric-dev --ci ok "$T/out-ok"
check "a fixture piece that follows the contract is accepted" [ "$(repos "$T/out-ok")" = "gitleaks a " ]
# A piece without a final newline still gives one well-formed repo: line per piece.
fx nonl ok "$good"
printf '  - repo: https://example.com/b\n    rev: v1.2.3\n    hooks:\n      - id: b' > "$T/nonl/nonl.yaml"
mkdir "$T/out-nonl"
ADD_CI_PIECES="$T/nonl" "$S" --org ouroboric-dev --ci nonl,ok "$T/out-nonl"
check "a piece without a final newline: one repo: line per piece" [ "$(repos "$T/out-nonl")" = "gitleaks b a " ]
check "a piece without a final newline: its last line stays whole" grep -qx '      - id: b' "$T/out-nonl/.pre-commit-config.yaml"

# Two pieces whose files clash.
mkdir -p "$T/clash/a.files" "$T/clash/b.files"
cp "$PIECES/gitleaks.yaml" "$T/clash/gitleaks.yaml"
printf '%s\n' "$good" > "$T/clash/a.yaml"
printf '%s\n' "$good" > "$T/clash/b.yaml"
echo 1 > "$T/clash/a.files/x"; echo 2 > "$T/clash/b.files/x"
mkdir "$T/out-clash"
ADD_CI_PIECES="$T/clash" "$S" --org ouroboric-dev --ci a,b "$T/out-clash" 2>/dev/null; rcc=$?
caseclash() { [ "$rcc" = 2 ] && empty "$T/out-clash"; }
check "two pieces with the same file are refused" caseclash

# --upgrade: replace the known gitleaks-only config, and nothing else.
KNOWN="$HERE/../templates/ci/upgrade/gitleaks-only.yaml"
known_sha() { [ "$(sha256sum "$KNOWN" | cut -c1-16)" = 7119399c9a531c4a ]; }
check "the known file is the old scaffold's" known_sha
mkdir "$T/up1" "$T/up2" "$T/up3" "$T/up4" "$T/up5"
for d in up1 up2 up3 up4 up5; do cp "$KNOWN" "$T/$d/.pre-commit-config.yaml"; done
"$S" --org ouroboric-dev --ci reuse,markdown --upgrade "$T/up1"; rcu1=$?
caseup1() {
  [ "$rcu1" = 0 ] && [ "$(repos "$T/up1")" = "gitleaks reuse-tool markdownlint-cli2 " ] &&
    cmp -s "$HERE/../templates/ci/lint.yml" "$T/up1/.github/workflows/lint.yml" &&
    [ -f "$T/up1/.markdownlint.yaml" ] && [ "$(head -n1 "$T/up1/.pre-commit-config.yaml")" = "repos:" ]
}
check "--upgrade replaces the known gitleaks-only config" caseup1
echo '      - id: extra' >> "$T/up2/.pre-commit-config.yaml"
"$S" --org ouroboric-dev --upgrade "$T/up2" 2>"$T/up2.err"; rcu2=$?
caseup2() {
  [ "$rcu2" = 2 ] && [ "$(files "$T/up2")" = "./.pre-commit-config.yaml " ] &&
    [ "$(tail -n1 "$T/up2/.pre-commit-config.yaml")" = '      - id: extra' ] &&
    grep -qxF "add-ci: $T/up2/.pre-commit-config.yaml is not the known gitleaks-only file; nothing was written" "$T/up2.err"
}
check "--upgrade refuses a changed config" caseup2
echo >> "$T/up3/.pre-commit-config.yaml"
"$S" --org ouroboric-dev --upgrade "$T/up3" 2>/dev/null; rcu3=$?
caseup3() { [ "$rcu3" = 2 ] && [ "$(files "$T/up3")" = "./.pre-commit-config.yaml " ] && ! cmp -s "$KNOWN" "$T/up3/.pre-commit-config.yaml"; }
check "--upgrade refuses a trailing blank line" caseup3
"$S" --org ouroboric-dev "$T/up4" 2>/dev/null; rcu4=$?
caseup4() { [ "$rcu4" = 2 ] && [ "$(files "$T/up4")" = "./.pre-commit-config.yaml " ] && cmp -s "$KNOWN" "$T/up4/.pre-commit-config.yaml"; }
check "without --upgrade the known config is refused" caseup4
mkdir -p "$T/up5/.github/workflows"
echo mine > "$T/up5/.github/workflows/lint.yml"
"$S" --org ouroboric-dev --upgrade "$T/up5" 2>/dev/null; rcu5=$?
caseup5() { [ "$rcu5" = 2 ] && [ "$(files "$T/up5")" = "./.github/workflows/lint.yml ./.pre-commit-config.yaml " ] && cmp -s "$KNOWN" "$T/up5/.pre-commit-config.yaml"; }
check "--upgrade still refuses an existing lint.yml" caseup5
"$S" --org ouroboric-dev --check --upgrade; cu=$?
caseup6() { [ "$cu" = 0 ]; }
check "--check --upgrade writes nothing and passes" caseup6

# --check.
mkdir "$T/chk"
"$S" --org ouroboric-dev --check; c1=$?
"$S" --org ouroboric-dev --ci shell,yaml --check; c2=$?
"$S" --org ouroboric-dev --ci nope --check 2>/dev/null; c3=$?
"$S" --org ouroboric-dev --ci a,, --check 2>/dev/null; c4=$?
casechk() { [ "$c1$c2$c3$c4" = 0022 ] && empty "$T/chk"; }
check "--check validates and writes nothing" casechk

# Every shipped piece passes the contract.
all() {
  local p names=()
  for p in "$PIECES"/*.yaml; do p="$(basename "$p" .yaml)"; names+=("$p"); done
  "$S" --org ouroboric-dev --ci "$(IFS=,; echo "${names[*]}")" --check
}
check "every shipped piece passes the contract" all

# The real run: the ouroboric-dev licence files, every piece, and a README (new-repo.sh adds one to each
# first commit so that no licence text is unused), in one commit.
pc() { uvx -q --from 'pre-commit==4.6.2' pre-commit "$@"; }
R="$T/real"
mkdir "$R"
git -C "$R" init -q -b main
"$HERE/../add-licences.sh" --org ouroboric-dev --year 2026 "$R"
"$S" --org ouroboric-dev --ci reuse,markdown,shell,actions,yaml "$R"
printf '# trial\n\nTrial of the base CI.\n' > "$R/README.md"
git -C "$R" add -- .
git -C "$R" -c user.name=t -c user.email=t@example.com commit -q -m "first"
validate() { (cd "$R" && pc validate-config .pre-commit-config.yaml); }
runall() { (cd "$R" && pc run --all-files >"$T/run.log" 2>&1) || { cat "$T/run.log"; return 1; }; }
hist() { (cd "$R" && pc run --hook-stage manual gitleaks-history --all-files >"$T/hist.log" 2>&1) || { cat "$T/hist.log"; return 1; }; }
check "pre-commit validate-config passes" validate
check "pre-commit run --all-files passes" runall
check "gitleaks-history passes on the first commit" hist
printf 'token = "ghp_%s"\n' "$(head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$R/leak.txt"
git -C "$R" add -- leak.txt
git -C "$R" -c user.name=t -c user.email=t@example.com commit -q -m "leak"
histfail() { ! hist >/dev/null 2>&1; }
check "gitleaks-history fails after a token-shaped string is committed" histfail

exit $fail

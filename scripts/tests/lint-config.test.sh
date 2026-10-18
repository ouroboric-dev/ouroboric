#!/usr/bin/env bash
# Tests for the shared lint config (the markdown and yaml pieces).   scripts/tests/lint-config.test.sh
# Every case is a real run: add-ci.sh --ci markdown,yaml in a temp git repo, then pre-commit run --all-files.
# They need the network the first time, as add-ci.test.sh does.
# shellcheck disable=SC2329,SC2016  # the case functions are called by check; the printf texts hold literal backticks
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../add-ci.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
pc() { uvx -q --from 'pre-commit==4.6.2' pre-commit "$@"; }

# mk <name>: a git repo with the markdown and yaml pieces. The caller adds files, then runs lint.
mk() {
  mkdir -p "$T/$1"
  git -C "$T/$1" init -q -b main
  "$S" --org ouroboric-dev --ci markdown,yaml "$T/$1"
}
# lint <name>: stage everything and run the hooks. Output goes to $T/<name>.log; the exit code is returned.
lint() {
  git -C "$T/$1" add -- .
  (cd "$T/$1" && pc run --all-files >"$T/$1.log" 2>&1)
}
passes() { lint "$1" || { cat "$T/$1.log"; return 1; }; }
fails_on() { # fails_on <name> <text>: the run fails, and the output holds <text>
  ! lint "$1" && grep -q -- "$2" "$T/$1.log"
}

# MD010: a tab inside a fenced code block is fine (gofmt), a tab in prose is not.
mk gotab
printf '# Doc\n\nCode:\n\n```go\nfunc main() {\n\treturn\n}\n```\n' > "$T/gotab/doc.md"
check "a tab in a Go code block passes" passes gotab
mk prosetab
printf '# Doc\n\nSome\ttext with a tab.\n' > "$T/prosetab/doc.md"
check "a tab in prose fails" fails_on prosetab MD010

# MD033: <picture> is allowed, <div> is not.
mk picture
printf '# Doc\n\n<picture>\n<source srcset="a.png">\n<img src="b.png" alt="b">\n</picture>\n' > "$T/picture/doc.md"
check "<picture> passes" passes picture
mk div
printf '# Doc\n\n<div>text</div>\n' > "$T/div/doc.md"
check "<div> fails" fails_on div MD033

# MD041: a file may open without an H1.
mk noh1
printf -- '---\ndate: 2026-10-18\n---\n\n## Challenge\n\nText.\n' > "$T/noh1/entry.md"
check "a journal-style file without an H1 passes" passes noh1

# markdownlint-cli2 ignores skip testdata, and the shared rules still apply to everything else.
mk mdx
printf 'ignores: ["testdata/**"]\n' > "$T/mdx/.markdownlint-cli2.yaml"
mkdir "$T/mdx/testdata" "$T/mdx/docs"
printf '# Doc\n\n<div>broken</div>\n' > "$T/mdx/testdata/x.md"
mdx() { # only docs/y.md is flagged, and by a rule from the shared file
  ! lint mdx && grep -q '^docs/y.md:' "$T/mdx.log" && ! grep -q '^testdata/x.md:' "$T/mdx.log" && grep -q MD033 "$T/mdx.log"
}
printf '# Doc\n\n<div>broken</div>\n' > "$T/mdx/docs/y.md"
check "markdownlint-cli2 ignores skip testdata and keep the shared rules" mdx

# A .yamllint that extends the shared config skips testdata and keeps the shared rules.
mk yx
printf 'extends: .yamllint.yaml\nignore: testdata/\n' > "$T/yx/.yamllint"
mkdir "$T/yx/testdata"
long="$(printf 'a%.0s' $(seq 1 130))"
printf 'key: %s\n' "$long" > "$T/yx/testdata/x.yaml"
printf 'key: %s\n' "$long" > "$T/yx/y.yaml"
yx() { # only y.yaml is flagged, on line-length from the shared file
  ! lint yx && grep -q 'y.yaml' "$T/yx.log" && ! grep -q 'testdata/x.yaml' "$T/yx.log" && grep -q 'line-length' "$T/yx.log"
}
check "a .yamllint that extends the shared config skips testdata and keeps its rules" yx

exit $fail

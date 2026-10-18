#!/usr/bin/env bash
# Tests for md-same-text.sh.   scripts/tests/md-same-text.test.sh
# Each case is a git repo in a temp folder with two commits (base, head) of one file, then a real run.
# They need the network the first time (uvx fetches the pinned markdown-it-py).
# shellcheck disable=SC2329,SC2016  # the case functions are called by check; the printf texts hold literal backticks
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../md-same-text.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }

# mk <name> <base text|-> <head text|->: a repo with doc.md at base and at head ("-" = no file at that commit).
mk() {
  local r="$T/$1"
  mkdir -p "$r"
  git -C "$r" init -q -b main
  git -C "$r" config user.email t@example.com
  git -C "$r" config user.name t
  printf 'x\n' >"$r/keep.txt"
  [ "$2" = - ] || printf '%b' "$2" >"$r/doc.md"
  git -C "$r" add -- .
  git -C "$r" commit -q -m base
  git -C "$r" tag base
  [ "$2" = - ] || rm -f -- "$r/doc.md"
  [ "$3" = - ] || printf '%b' "$3" >"$r/doc.md"
  git -C "$r" add -A -- .
  git -C "$r" commit -q --allow-empty -m head
}
# runs <name> <want exit> <want output line>
runs() {
  local out rc
  out="$(cd "$T/$1" && "$S" base HEAD 2>&1)"; rc=$?
  [ "$rc" = "$2" ] && [ "$out" = "$3" ]
}

c_blank() { mk blank '# T\ntext\n## H\nmore\n' '# T\n\ntext\n\n## H\n\nmore\n'; runs blank 0 'same doc.md'; }
c_table() { mk table '|a|b|\n|---|---|\n|1|2|\n' '| a | b |\n| --- | --- |\n| 1 | 2 |\n'; runs table 0 'same doc.md'; }
c_bold() { mk bold '**X**\n\ntext\n' '#### X\n\ntext\n'; runs bold 0 'same doc.md'; }
c_info() { mk info '```\nfoo\n```\n' '```text\nfoo\n```\n'; runs info 0 'same doc.md'; }
c_word() { mk word 'one two\n' 'one three\n'; runs word 1 'DIFFERS doc.md: text'; }
c_tab() { mk tab '```go\n\tx := 1\n```\n' '```go\n    x := 1\n```\n'; runs tab 1 'DIFFERS doc.md: code'; }
c_trail() { mk trail '```go\nx := 1\n```\n' '```go\nx := 1 \n```\n'; runs trail 1 'DIFFERS doc.md: code'; }
c_line() { mk line '```go\nx := 1\n```\n' '```go\nx := 1\ny := 2\n```\n'; runs line 1 'DIFFERS doc.md: code'; }
c_link() { mk link '[t](http://a.com)\n' '[t](http://evil.com)\n'; runs link 1 'DIFFERS doc.md: links'; }
c_img() { mk img '![alt](a.png)\n' '![alt](b.png)\n'; runs img 1 'DIFFERS doc.md: links'; }
c_ref() { mk ref '[t][1]\n\n[1]: http://a.com\n' '[t][1]\n\n[1]: http://evil.com\n'; runs ref 1 'DIFFERS doc.md: links'; }
c_html() { mk html '<a href="x">t</a>\n' '<a href="y">t</a>\n'; runs html 1 'DIFFERS doc.md: links'; }
c_autolink() { mk autolink 'see https://a.com/x now\n' 'see <https://a.com/x> now\n'; runs autolink 0 'same doc.md'; }
c_placeholder() { mk placeholder 'Run it with <issue> set.\n' 'Run it with `<issue>` set.\n'; runs placeholder 0 'same doc.md'; }
c_rawtext() { mk rawtext 'see <abbr title="one">X</abbr>\n' 'see <abbr title="two">X</abbr>\n'; runs rawtext 1 'DIFFERS doc.md: text'; }
c_lintoff() { mk lintoff '# T\n\nA long line.\n' '# T\n\n<!-- markdownlint-disable-next-line MD013 -->\nA long line.\n'; runs lintoff 1 'DIFFERS doc.md: lintoff'; }
c_indent() { mk indent 'para\n\n\tcode  x\n' 'para\n\n\tcode x\n'; runs indent 1 'DIFFERS doc.md: code'; }
c_planfence() { mk planfence '```diff\n+a\n ```\n-  item\n+x  \n```\n' '```diff\n+a\n ```\n- item\n+x\n```\n'; runs planfence 1 'DIFFERS doc.md: code'; }
c_planbash() { mk planbash '```\nfoo\n```\n' '```bash\nfoo\n```\n'; runs planbash 1 'DIFFERS doc.md: code'; }
c_added() { mk added - 'new\n'; runs added 1 'DIFFERS doc.md: added'; }
c_deleted() { mk deleted 'old\n' -; runs deleted 1 'DIFFERS doc.md: deleted'; }
c_nomd() { mk nomd - -; runs nomd 0 ''; }
c_badref() { (cd "$T/nomd" && "$S" nosuchref HEAD >/dev/null 2>&1; [ "$?" = 2 ]); }
c_usage() { (cd "$T/nomd" && "$S" base >/dev/null 2>&1; [ "$?" = 2 ]); }

check "a heading with blank lines added is the same" c_blank
check "|---| to | --- | is the same" c_table
check "**X** to #### X is the same" c_bold
check "a fence given an info string is the same" c_info
check "a changed word differs (text)" c_word
check "a tab changed to spaces in a fence differs (code)" c_tab
check "trailing whitespace in a fence differs (code)" c_trail
check "a line added in a fence differs (code)" c_line
check "a changed link target differs" c_link
check "a changed image src differs" c_img
check "a changed reference definition differs" c_ref
check "a changed raw HTML href differs" c_html
check "a whitespace change in an indented code block differs" c_indent
check "a bare URL wrapped as <URL> is the same" c_autolink
check "a placeholder wrapped in backticks is the same" c_placeholder
check "changed raw HTML text differs" c_rawtext
check "an added markdownlint-disable comment differs" c_lintoff
check "a fix inside a plan-style diff block that CommonMark closes early differs" c_planfence
check "a bare plan fence given a bash info string differs" c_planbash
check "a file only in head reports added" c_added
check "a file only in base reports deleted" c_deleted
check "no .md change exits 0" c_nomd
check "a bad ref exits 2" c_badref
check "missing arguments exit 2" c_usage
exit $fail

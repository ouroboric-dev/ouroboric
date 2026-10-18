#!/usr/bin/env bash
# Prove that a Markdown change is formatting only. An agent runs it after `markdownlint-cli2 --fix`.
#   md-same-text.sh <base-ref> <head-ref>      run inside a git repo; it reads only, and needs no token
# For each .md file changed between the refs it prints `same <file>` or `DIFFERS <file>: <why>`:
#   text   the rendered text differs (whitespace and markup are ignored)
#   code   a fenced code block differs by any byte, even a tab or a trailing space
#   added / deleted   the file exists in only one ref
# Exit 0 if every file is the same or no .md file changed, 1 if any differs, 2 on bad input.
# The renderer is md-same-text.py, with markdown-it-py pinned, run by uvx as `python3 -I`.
set -euo pipefail
die() { echo "md-same-text.sh: $*" >&2; exit 2; }
[ $# -eq 2 ] || die "usage: md-same-text.sh <base-ref> <head-ref>"
git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repo"
for r in "$1" "$2"; do git rev-parse --verify --quiet "$r^{commit}" >/dev/null || die "bad ref: $r"; done
PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/md-same-text.py"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
diff_names() { git diff -z --no-renames --name-only --diff-filter="$1" "$2" "$3" -- '*.md'; }
while IFS= read -r -d '' f; do echo "DIFFERS $f: added"; fail=1; done < <(diff_names A "$1" "$2")
while IFS= read -r -d '' f; do echo "DIFFERS $f: deleted"; fail=1; done < <(diff_names D "$1" "$2")
while IFS= read -r -d '' f; do
  git show "$1:$f" >"$T/old.md"
  git show "$2:$f" >"$T/new.md"
  v="$(uvx -q --with 'markdown-it-py==3.0.0' python3 -I "$PY" "$T/old.md" "$T/new.md")"
  if [ "$v" = same ]; then echo "same $f"; else echo "DIFFERS $f: $v"; fail=1; fi
done < <(diff_names M "$1" "$2")
exit $fail

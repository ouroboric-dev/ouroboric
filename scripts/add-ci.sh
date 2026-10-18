#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Write the base CI into a folder: .pre-commit-config.yaml (the pieces, in order), .github/workflows/lint.yml
# and the files that some pieces ship (such as .markdownlint.yaml). The pieces come from --ci, or else from the
# org config's "ci" list; gitleaks is always first. templates/ci/README.md has the piece format.
# If any target exists, a folder it goes in is not a folder, or any piece breaks the format, it exits 2
# and writes nothing. A piece without a final newline gets one.
# Run by new-repo.sh; the founder can also run it on any existing folder.
#   add-ci.sh (--org <name>|--config <path>) [--ci <piece>,...] (--check | <dir>)
# --check validates the pieces and writes nothing. ADD_CI_PIECES replaces the pieces folder.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "add-ci: $*" >&2; exit 2; }
# shellcheck source=repo-config.sh
. "$HERE/repo-config.sh"

usage='usage: add-ci.sh (--org <name>|--config <path>) [--ci <piece>,...] (--check | <dir>)'
repo_config_args "$@"
repo_config_load
ci='' have_ci='' check='' dir=''
set -- "${RC_REST[@]}"
while [ $# -gt 0 ]; do
  case "$1" in
    --ci) [ $# -ge 2 ] && [ -n "$2" ] || die "--ci needs a value"; ci="$2"; have_ci=1; shift ;;
    --check) check=1 ;;
    -*) die "$usage" ;;
    *) [ -z "$dir" ] || die "$usage"; dir="$1" ;;
  esac
  shift
done
if [ -n "$check" ]; then
  [ -z "$dir" ] || die "$usage"
else
  [ -n "$dir" ] || die "$usage"
  [ -d "$dir" ] || die "$dir: no such folder"
fi
[ -n "$have_ci" ] || ci="$RC_CI"
pieces_dir="${ADD_CI_PIECES:-$HERE/templates/ci/pieces}"

# The list: gitleaks first, then --ci in order, each name once. An empty item is an error.
names=(gitleaks)
if [ -n "$ci" ]; then
  # A trailing comma would vanish in read -a, so add a sentinel.
  IFS=, read -r -a items <<< "$ci,x"
  unset 'items[${#items[@]}-1]'
  for item in "${items[@]}"; do
    [ -n "$item" ] || die "--ci has an empty item: $ci"
    [[ "$item" =~ ^[a-z0-9-]+$ ]] || die "$item: a piece name is lower-case letters, digits and hyphens"
    dup=''
    for n in "${names[@]}"; do [ "$n" != "$item" ] || dup=1; done
    [ -n "$dup" ] || names+=("$item")
  done
fi

# Check each piece against the format.
rev_re='^v?[0-9]+(\.[0-9]+)+([.-][0-9A-Za-z]+)*$'
for n in "${names[@]}"; do
  f="$pieces_dir/$n.yaml"
  [ -f "$f" ] || die "$n: no such piece ($f)"
  [ "$(grep -c '^  - repo: https://' "$f")" = 1 ] || die "$n: it needs exactly one line starting '  - repo: https://'"
  [ "$(grep -c '^    rev: ' "$f")" = 1 ] || die "$n: it needs exactly one line starting '    rev: '"
  rev="$(grep '^    rev: ' "$f")"; rev="${rev#    rev: }"
  [[ "$rev" =~ $rev_re ]] || die "$n: rev must be a release tag such as v1.2.3, not '$rev'"
  grep -q '^    hooks:' "$f" || die "$n: it needs a line starting '    hooks:'"
  ! grep -q $'\t' "$f" || die "$n: it must not contain tabs"
done

# The files that pieces ship; two pieces must not ship the same path.
extra=() src=()
for n in "${names[@]}"; do
  [ -d "$pieces_dir/$n.files" ] || continue
  while IFS= read -r -d '' p; do
    rel="${p#"$pieces_dir/$n.files/"}"
    for e in "${extra[@]+"${extra[@]}"}"; do [ "$e" != "$rel" ] || die "$n: the file $rel is also shipped by another piece"; done
    extra+=("$rel") src+=("$p")
  done < <(find "$pieces_dir/$n.files" -type f -print0 | LC_ALL=C sort -z)
done
lint="$HERE/templates/ci/lint.yml"
[ -f "$lint" ] || die "$lint: no such template"
[ -z "$check" ] || exit 0

# Check every target, and every folder it goes in, before writing any.
targets=(.pre-commit-config.yaml .github/workflows/lint.yml "${extra[@]+"${extra[@]}"}")
for f in "${targets[@]}"; do
  [ ! -e "$dir/$f" ] && [ ! -L "$dir/$f" ] || die "$dir/$f exists; nothing was written"
  p="$(dirname "$f")"
  while [ "$p" != . ]; do
    [ -d "$dir/$p" ] || { [ ! -e "$dir/$p" ] && [ ! -L "$dir/$p" ]; } || die "$dir/$p is not a folder; nothing was written"
    p="$(dirname "$p")"
  done
done

# A piece's last line may lack its newline; add one, so the next piece starts on its own line.
{
  echo "repos:"
  for n in "${names[@]}"; do
    cat -- "$pieces_dir/$n.yaml"
    [ -z "$(tail -c 1 -- "$pieces_dir/$n.yaml")" ] || echo
  done
} > "$dir/.pre-commit-config.yaml"
mkdir -p "$dir/.github/workflows"
cp -- "$lint" "$dir/.github/workflows/lint.yml"
for i in "${!extra[@]}"; do
  mkdir -p "$(dirname "$dir/${extra[$i]}")"
  cp -- "${src[$i]}" "$dir/${extra[$i]}"
done

#!/usr/bin/env bash
# Write the licence files that an org config names into a folder: LICENSES/<licence>.txt,
# LICENSES/<docs_licence>.txt (if the config has one), LICENSE (a copy of the code licence's text) and
# REUSE.toml. The texts come from the config's licence_dir, or from "reuse download" if it has none.
# If any target exists or any text is missing, it exits 2 and writes nothing.
# Run by new-repo.sh; the founder or an agent can run it on any existing folder.
#   add-licences.sh (--org <name>|--config <path>) [--year <yyyy>] (--check | <dir>)
# --check finds each text (in licence_dir, or by the reuse command being on PATH) and writes nothing.
# --year defaults to this year. ADD_LICENCES_REUSE replaces the reuse command (default: uvx, pinned).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "add-licences: $*" >&2; exit 2; }
# shellcheck source=repo-config.sh
. "$HERE/repo-config.sh"

usage='usage: add-licences.sh (--org <name>|--config <path>) [--year <yyyy>] (--check | <dir>)'
repo_config_args "$@"
repo_config_load
year='' check='' dir=''
set -- "${RC_REST[@]}"
while [ $# -gt 0 ]; do
  case "$1" in
    --year) [ $# -ge 2 ] || die "--year needs a value"; year="$2"; shift ;;
    --check) check=1 ;;
    -*) die "$usage" ;;
    *) [ -z "$dir" ] || die "$usage"; dir="$1" ;;
  esac
  shift
done
year="${year:-$(date +%Y)}"
[[ "$year" =~ ^[0-9]{4}$ ]] || die "the year must be four digits: $year"
if [ -n "$check" ]; then
  [ -z "$dir" ] || die "$usage"
else
  [ -n "$dir" ] || die "$usage"
  [ -d "$dir" ] || die "$dir: no such folder"
fi

ids=("$RC_LICENCE")
[ -z "$RC_DOCS_LICENCE" ] || ids+=("$RC_DOCS_LICENCE")
read -r -a reuse <<< "${ADD_LICENCES_REUSE:-uvx -q --from reuse==5.0.2 reuse}"
[ "${#reuse[@]}" -gt 0 ] || die "ADD_LICENCES_REUSE is empty"

# Find every text before anything is written.
if [ -n "$RC_LICENCE_DIR" ]; then
  for id in "${ids[@]}"; do
    [ -f "$RC_LICENCE_DIR/$id.txt" ] || die "$RC_LICENCE_DIR/$id.txt: no such licence text; nothing was written"
  done
else
  command -v "${reuse[0]}" >/dev/null 2>&1 || die "${reuse[0]} is not on PATH, so the licence texts can't be downloaded"
fi
[ -z "$check" ] || exit 0

# Check every target before writing any.
targets=(LICENSE REUSE.toml)
for id in "${ids[@]}"; do targets+=("LICENSES/$id.txt"); done
for f in "${targets[@]}"; do
  [ ! -e "$dir/$f" ] && [ ! -L "$dir/$f" ] || die "$dir/$f exists; nothing was written"
done

# Gather the texts in a staging folder, so a download that fails part way leaves $dir untouched.
T="$(mktemp -d)"
trap 'rm -rf -- "${T:?}"' EXIT
mkdir "$T/texts"
for id in "${ids[@]}"; do
  if [ -n "$RC_LICENCE_DIR" ]; then
    cp -- "$RC_LICENCE_DIR/$id.txt" "$T/texts/$id.txt"
  else
    mkdir -p "$T/dl"
    (cd "$T/dl" && "${reuse[@]}" download "$id" >/dev/null) || die "reuse download $id failed; nothing was written"
    [ -s "$T/dl/LICENSES/$id.txt" ] || die "reuse download $id gave no text; nothing was written"
    cp -- "$T/dl/LICENSES/$id.txt" "$T/texts/$id.txt"
  fi
done

{
  printf 'version = 1\n\n[[annotations]]\npath = ["**"]\nprecedence = "closest"\n'
  printf 'SPDX-FileCopyrightText = "%s %s"\nSPDX-License-Identifier = "%s"\n' "$year" "$RC_COPYRIGHT" "$RC_LICENCE"
  if [ -n "$RC_DOCS_LICENCE" ]; then
    printf '\n[[annotations]]\npath = [%s]\nprecedence = "closest"\n' "$RC_DOCS_PATHS"
    printf 'SPDX-FileCopyrightText = "%s %s"\nSPDX-License-Identifier = "%s"\n' "$year" "$RC_COPYRIGHT" "$RC_DOCS_LICENCE"
  fi
} > "$T/REUSE.toml"

mkdir -p "$dir/LICENSES"
for id in "${ids[@]}"; do cp -- "$T/texts/$id.txt" "$dir/LICENSES/$id.txt"; done
cp -- "$T/texts/$RC_LICENCE.txt" "$dir/LICENSE"
cp -- "$T/REUSE.toml" "$dir/REUSE.toml"

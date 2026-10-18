#!/usr/bin/env bash
# Tests for add-licences.sh.   scripts/tests/add-licences.test.sh
# "reuse lint passes" runs the real reuse tool through uvx (it needs the network the first time).
# shellcheck disable=SC2329  # the case functions are called by check
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../add-licences.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
LICENSES="$HERE/../../LICENSES"

# The stub reuse writes "TEXT <id>" to LICENSES/<id>.txt in the current folder.
mkdir "$T/bin"
cat > "$T/bin/reuse" <<'STUB'
#!/usr/bin/env bash
[ "$1" = download ] || exit 1
mkdir -p LICENSES
printf 'TEXT %s\n' "$2" > "LICENSES/$2.txt"
STUB
chmod +x "$T/bin/reuse"

case1() { [ "$(files "$T/one")" = "./LICENSE ./LICENSES/MIT.txt ./REUSE.toml " ] && [ "$(cat "$T/one/LICENSES/MIT.txt")" = "TEXT MIT" ] && [ "$(cat "$T/one/LICENSE")" = "TEXT MIT" ]; }
case2() { [ "$rc" = 2 ] && [ "$(files "$T/ex")" = "./REUSE.toml " ] && [ "$(cat "$T/ex/REUSE.toml")" = mine ]; }
case3() { [ "$rc" = 2 ] && empty "$T/miss"; }
case4() { [ "$rc" = 2 ] && empty "$T/half"; }
case5() { [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ "$rc3" = 2 ] && [ "$rc4" = 2 ] && empty "$T/chk"; }
case6() { [ "$rc" = 2 ] && empty "$T/chk"; }

# Today's REUSE.toml, from create-repo.sh at a6be975.
cat > "$T/golden.toml" <<'EOF2'
version = 1

[[annotations]]
path = ["**"]
precedence = "closest"
SPDX-FileCopyrightText = "2026 Bruno Guilhermo de Barros Valério"
SPDX-License-Identifier = "AGPL-3.0-only"

[[annotations]]
path = ["docs/**", "README.md", "AGENTS.md"]
precedence = "closest"
SPDX-FileCopyrightText = "2026 Bruno Guilhermo de Barros Valério"
SPDX-License-Identifier = "CC-BY-4.0"
EOF2

cfg() { printf '%s\n' "$2" > "$T/$1.json"; }
files() { (cd "$1" && find . -type f | LC_ALL=C sort | tr '\n' ' '); }
empty() { [ -z "$(ls -A "$1")" ]; }

mkdir "$T/dev"
"$S" --org ouroboric-dev --year 2026 "$T/dev"
check "ouroboric-dev: the four files" \
  [ "$(files "$T/dev")" = "./LICENSE ./LICENSES/AGPL-3.0-only.txt ./LICENSES/CC-BY-4.0.txt ./REUSE.toml " ]
check "REUSE.toml is today's, byte for byte" cmp -s "$T/golden.toml" "$T/dev/REUSE.toml"
check "LICENSE is the AGPL text" cmp -s "$LICENSES/AGPL-3.0-only.txt" "$T/dev/LICENSE"

# A config with no licence_dir and one licence.
cfg one '{"org": "acme", "licence": "MIT", "copyright": "Acme"}'
mkdir "$T/one"
ADD_LICENCES_REUSE="$T/bin/reuse" "$S" --config "$T/one.json" --year 2025 "$T/one"
check "one licence: one annotation" \
  [ "$(cat "$T/one/REUSE.toml")" = 'version = 1

[[annotations]]
path = ["**"]
precedence = "closest"
SPDX-FileCopyrightText = "2025 Acme"
SPDX-License-Identifier = "MIT"' ]
check "no licence_dir: reuse download" case1

# An existing target: exit 2, nothing else written.
mkdir "$T/ex"
echo mine > "$T/ex/REUSE.toml"
"$S" --org ouroboric-dev --year 2026 "$T/ex" 2>/dev/null; rc=$?
check "an existing REUSE.toml: nothing is written" case2

# A missing text in licence_dir: exit 2, nothing written.
mkdir "$T/lic" "$T/miss"
echo A > "$T/lic/AGPL-3.0-only.txt"
cfg miss '{"org": "acme", "licence": "AGPL-3.0-only", "docs_licence": "CC-BY-4.0", "docs_paths": ["docs/**"], "copyright": "Acme", "licence_dir": "lic"}'
"$S" --config "$T/miss.json" --year 2026 "$T/miss" 2>/dev/null; rc=$?
check "a missing text: nothing is written" case3

# A failing reuse download part way: nothing is written.
cat > "$T/bin/reuse-half" <<'STUB'
#!/usr/bin/env bash
mkdir -p LICENSES
[ "$2" = MIT ] || exit 1
printf 'TEXT %s\n' "$2" > "LICENSES/$2.txt"
STUB
chmod +x "$T/bin/reuse-half"
cfg half '{"org": "acme", "licence": "MIT", "docs_licence": "CC-BY-4.0", "docs_paths": ["docs/**"], "copyright": "Acme"}'
mkdir "$T/half"
ADD_LICENCES_REUSE="$T/bin/reuse-half" "$S" --config "$T/half.json" --year 2026 "$T/half" 2>/dev/null; rc=$?
check "a failed download part way: nothing is written" case4

# --check.
mkdir "$T/chk"
"$S" --org ouroboric-dev --check; rc1=$?
ADD_LICENCES_REUSE="$T/bin/reuse" "$S" --config "$T/one.json" --check; rc2=$?
ADD_LICENCES_REUSE="$T/nope" "$S" --config "$T/one.json" --check 2>/dev/null; rc3=$?
"$S" --config "$T/miss.json" --check 2>/dev/null; rc4=$?
check "--check writes nothing" case5

# Bad year.
"$S" --org ouroboric-dev --year 26 "$T/chk" 2>/dev/null; rc=$?
check "a year of other than four digits is refused" case6

# The real tool.
# reuse lint ignores the licence files themselves, and flags unused texts, so give each licence a file.
lint() { git -C "$T/dev" init -q && mkdir "$T/dev/docs" && echo code > "$T/dev/main.py" && echo doc > "$T/dev/docs/a.md" && (cd "$T/dev" && uvx -q --from 'reuse==5.0.2' reuse lint >/dev/null); }
check "reuse lint passes" lint

exit $fail

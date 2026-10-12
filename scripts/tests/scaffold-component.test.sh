#!/usr/bin/env bash
# Tests for scaffold-component.sh on a local repo laid out like create-repo.sh's first commit.
#   scripts/tests/scaffold-component.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD="$HERE/../scaffold-component.sh"
LICENSES="$HERE/../../LICENSES"
MIT="$HERE/../../../asgard/LICENSES/MIT.txt"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
newrepo() { # newrepo DIR: the files create-repo.sh's first commit holds
  mkdir -p "$1/LICENSES" && git init -q "$1"
  cp "$LICENSES/AGPL-3.0-only.txt" "$LICENSES/CC-BY-4.0.txt" "$1/LICENSES/"
  cp "$LICENSES/AGPL-3.0-only.txt" "$1/LICENSE"
  printf '%s\n' 'version = 1' '' '[[annotations]]' 'path = ["**"]' 'precedence = "closest"' \
    'SPDX-FileCopyrightText = "2026 Bruno Guilhermo de Barros Valério"' 'SPDX-License-Identifier = "AGPL-3.0-only"' '' \
    '[[annotations]]' 'path = ["docs/**", "README.md", "AGENTS.md"]' 'precedence = "closest"' \
    'SPDX-FileCopyrightText = "2026 Bruno Guilhermo de Barros Valério"' 'SPDX-License-Identifier = "CC-BY-4.0"' > "$1/REUSE.toml"
  git -C "$1" add LICENSE LICENSES REUSE.toml
  git -C "$1" -c user.name=Test -c user.email=test@example.invalid commit -qm Licences
}
JOB='The alpha job: reads `x.yaml` & writes a/b, with 100% of {{JOB}} kept.'

newrepo "$T/alpha"
"$SCAFFOLD" alpha "$JOB" "$T/alpha" > "$T/out" 2>&1; rc=$?
check "exit 0" [ "$rc" = 0 ]
check "it writes the scaffold files" \
  [ "$(cd "$T/alpha" && git status --short --untracked-files=all | sort | tr '\n' ' ')" = "?? .devcontainer/devcontainer.json ?? .gitignore ?? AGENTS.md ?? README.md ?? docs/architecture.md ?? go.mod " ]
check "go.mod names the module and Go 1.26" \
  [ "$(cat "$T/alpha/go.mod")" = "$(printf 'module github.com/ouroboric-dev/alpha\n\ngo 1.26')" ]
check "the job sentence is copied exactly, special characters included" \
  bash -c "grep -qxF -- \"\$1\" '$T/alpha/AGENTS.md' && grep -qxF -- \"\$1\" '$T/alpha/README.md' && grep -qxF -- \"\$1\" '$T/alpha/docs/architecture.md'" _ "$JOB"
check "AGENTS.md passes the leaf rules: short, links the invariants, no invariants of its own" \
  bash -c "[ \$(wc -l < '$T/alpha/AGENTS.md') -le 120 ] && grep -q 'ouroboric-dev/yggdrasil/blob/main/AGENTS.md#invariants' '$T/alpha/AGENTS.md' && ! grep -q '^## Invariants' '$T/alpha/AGENTS.md'"
check "the devcontainer pins the Go image by digest" \
  grep -q '"image": "docker.io/library/golang:[0-9.]*-bookworm@sha256:[0-9a-f]\{64\}"' "$T/alpha/.devcontainer/devcontainer.json"
check "the architecture doc has front matter with the reference style and today's date" \
  bash -c "head -7 '$T/alpha/docs/architecture.md' | grep -qx 'title: Alpha architecture' && grep -qx 'style: reference' '$T/alpha/docs/architecture.md' && grep -qx \"date: \$(date +%F)\" '$T/alpha/docs/architecture.md'"
check "the architecture doc leaves Responsibilities and Depends on for a person to write" \
  bash -c "grep -A2 '^## Responsibilities' '$T/alpha/docs/architecture.md' | grep -q '<!--' && grep -A2 '^## Depends on' '$T/alpha/docs/architecture.md' | grep -q '<!--'"
check "the output says what to write next" grep -q 'docs/architecture.md' "$T/out"
check "no template marker is left, except the one inside the job sentence" \
  bash -c "[ \$(cat '$T/alpha/go.mod' '$T/alpha/.gitignore' '$T/alpha/.devcontainer/devcontainer.json' | grep -c '{{') = 0 ] && [ \$(grep -c '{{' '$T/alpha/AGENTS.md') = 1 ]"
check "reuse lint passes" bash -c "cd '$T/alpha' && uvx -q --from 'reuse==5.0.2' reuse lint -q"
if command -v go >/dev/null; then
  cp "$T/alpha/go.mod" "$T/go.mod.before"
  check "go mod tidy leaves go.mod unchanged" bash -c "cd '$T/alpha' && GOTOOLCHAIN=local go mod tidy 2>/dev/null; cmp -s go.mod '$T/go.mod.before'"
fi

cp "$T/alpha/AGENTS.md" "$T/agents.before"
"$SCAFFOLD" alpha "Another job." "$T/alpha" 2>/dev/null; rc=$?
check "an existing scaffold file is never overwritten" bash -c "[ $rc = 2 ] && cmp -s '$T/agents.before' '$T/alpha/AGENTS.md'"

newrepo "$T/web"
"$SCAFFOLD" --mit-templates realm-web "The web realm." "$T/web" >/dev/null 2>&1; rc=$?
check "--mit-templates: exit 0" [ "$rc" = 0 ]
check "--mit-templates adds the MIT text and templates/README.md" \
  bash -c "cmp -s '$MIT' '$T/web/LICENSES/MIT.txt' && [ -f '$T/web/templates/README.md' ]"
check "--mit-templates makes templates/** MIT in REUSE.toml" \
  bash -c "grep -A3 'path = \[\"templates/\*\*\"\]' '$T/web/REUSE.toml' | grep -q 'SPDX-License-Identifier = \"MIT\"'"
check "a hyphenated name keeps its case in the title" grep -qx 'title: realm-web architecture' "$T/web/docs/architecture.md"
check "--mit-templates: reuse lint passes" bash -c "cd '$T/web' && uvx -q --from 'reuse==5.0.2' reuse lint -q"

mkdir "$T/plain"
"$SCAFFOLD" beta "The beta job." "$T/plain" 2>/dev/null; rc=$?
check "a folder without create-repo.sh's first commit is refused" bash -c "[ $rc = 2 ] && [ ! -e '$T/plain/go.mod' ]"
newrepo "$T/bad"
"$SCAFFOLD" ../bad "Bad." "$T/bad" 2>/dev/null; rc=$?
check "a bad repo name is refused" bash -c "[ $rc = 2 ] && [ ! -e '$T/bad/go.mod' ]"

exit $fail

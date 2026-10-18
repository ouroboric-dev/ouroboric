#!/usr/bin/env bash
# Tests for scaffold-component.sh on a local repo laid out like new-repo.sh's first commit.
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
newrepo() { # newrepo DIR [DESCRIPTION [REPO]]: the files new-repo.sh's first commit holds
  mkdir -p "$1/LICENSES" && git init -q "$1"
  cp "$LICENSES/AGPL-3.0-only.txt" "$LICENSES/CC-BY-4.0.txt" "$1/LICENSES/"
  cp "$LICENSES/AGPL-3.0-only.txt" "$1/LICENSE"
  printf '%s\n' 'version = 1' '' '[[annotations]]' 'path = ["**"]' 'precedence = "closest"' \
    'SPDX-FileCopyrightText = "2026 Bruno Guilhermo de Barros Valério"' 'SPDX-License-Identifier = "AGPL-3.0-only"' '' \
    '[[annotations]]' 'path = ["docs/**", "README.md", "AGENTS.md"]' 'precedence = "closest"' \
    'SPDX-FileCopyrightText = "2026 Bruno Guilhermo de Barros Valério"' 'SPDX-License-Identifier = "CC-BY-4.0"' > "$1/REUSE.toml"
  printf '%s\n' 'repos:' | cat - "$HERE/../templates/ci/pieces/gitleaks.yaml" > "$1/.pre-commit-config.yaml"
  printf '# %s\n\n%s\n' "${3:-$(basename "$1")}" "${2:-A stub description.}" > "$1/README.md"
  git -C "$1" add LICENSE LICENSES REUSE.toml .pre-commit-config.yaml README.md
  git -C "$1" -c user.name=Test -c user.email=test@example.invalid commit -qm Licences
}
JOB='The alpha job: reads `x.yaml` & writes a/b, with 100% of {{JOB}} kept.'

newrepo "$T/alpha" "$JOB"
"$SCAFFOLD" alpha "$JOB" "$T/alpha" > "$T/out" 2>&1; rc=$?
check "exit 0" [ "$rc" = 0 ]
check "it writes the scaffold files" \
  [ "$(cd "$T/alpha" && git status --short --untracked-files=all | sort | tr '\n' ' ')" = " M README.md ?? .devcontainer/devcontainer.json ?? .gitignore ?? AGENTS.md ?? docs/architecture.md ?? go.mod " ]
check "the gitleaks hook is pinned to v8.30.1, as check-repos.sh's gitleaks check wants" \
  bash -c "grep -q 'repo: https://github.com/gitleaks/gitleaks' '$T/alpha/.pre-commit-config.yaml' && grep -q 'rev: v8.30.1' '$T/alpha/.pre-commit-config.yaml'"
check "the README keeps its stub as its first three lines, then holds the template's sections" \
  bash -c "[ \"\$(head -3 '$T/alpha/README.md')\" = \"\$(printf '# alpha\n\n%s' \"\$1\")\" ] && grep -qx '## Build and test' '$T/alpha/README.md'" _ "$JOB"
check "the README says to install the hook" grep -qF 'Run `uvx pre-commit install` once after cloning' "$T/alpha/README.md"
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

cp "$T/alpha/.pre-commit-config.yaml" "$T/pc.before"
check "the pre-commit config stays as new-repo.sh made it" \
  bash -c "cmp -s '$T/pc.before' '$T/alpha/.pre-commit-config.yaml' && git -C '$T/alpha' diff --quiet -- .pre-commit-config.yaml"

newrepo "$T/web" "The Midgard realm's React flavor." midgard-react
"$SCAFFOLD" --mit-templates midgard-react "The Midgard realm's React flavor." "$T/web" >/dev/null 2>&1; rc=$?
check "--mit-templates: exit 0" [ "$rc" = 0 ]
check "--mit-templates adds the MIT text and templates/README.md" \
  bash -c "cmp -s '$MIT' '$T/web/LICENSES/MIT.txt' && [ -f '$T/web/templates/README.md' ]"
check "--mit-templates makes templates/** MIT in REUSE.toml" \
  bash -c "grep -A3 'path = \[\"templates/\*\*\"\]' '$T/web/REUSE.toml' | grep -q 'SPDX-License-Identifier = \"MIT\"'"
check "a hyphenated name keeps its case in the title" grep -qx 'title: midgard-react architecture' "$T/web/docs/architecture.md"
check "the README calls Yggdrasil the agentic factory" grep -q "the agentic factory by" "$T/web/README.md"
check "--mit-templates: reuse lint passes" bash -c "cd '$T/web' && uvx -q --from 'reuse==5.0.2' reuse lint -q"

mkdir "$T/plain"
"$SCAFFOLD" beta "The beta job." "$T/plain" 2>/dev/null; rc=$?
check "a folder without new-repo.sh's first commit is refused" bash -c "[ $rc = 2 ] && [ ! -e '$T/plain/go.mod' ]"
newrepo "$T/nopc"; git -C "$T/nopc" rm -qf .pre-commit-config.yaml
"$SCAFFOLD" gamma "Gamma." "$T/nopc" 2>/dev/null; rc=$?
check "a folder without .pre-commit-config.yaml is refused" bash -c "[ $rc = 2 ] && [ ! -e '$T/nopc/go.mod' ]"
newrepo "$T/norm"; git -C "$T/norm" rm -qf README.md
"$SCAFFOLD" delta "Delta." "$T/norm" 2>/dev/null; rc=$?
check "a folder without README.md is refused" bash -c "[ $rc = 2 ] && [ ! -e '$T/norm/go.mod' ] && [ ! -e '$T/norm/README.md' ]"
newrepo "$T/bad"
"$SCAFFOLD" ../bad "Bad." "$T/bad" 2>/dev/null; rc=$?
check "a bad repo name is refused" bash -c "[ $rc = 2 ] && [ ! -e '$T/bad/go.mod' ]"

exit $fail

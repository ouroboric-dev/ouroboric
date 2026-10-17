#!/usr/bin/env bash
# Write the scaffold of a new Yggdrasil Go component into a clone of its repo: go.mod, README.md,
# AGENTS.md, docs/architecture.md, the devcontainer, .gitignore and the pinned gitleaks pre-commit
# hook, from templates/go-component/.
# The repo must hold create-repo.sh's first commit. Never overwrites a file. The architecture doc's
# Responsibilities and Depends on are left for a person to write from the spec; then commit on a
# branch and open a PR. Agent-run.
#   scaffold-component.sh [--mit-templates] <repo> "<job sentence>" <clone dir>
# --mit-templates also adds an MIT-licensed templates/ folder, for repos whose templates are copied
# into products (such as midgard-react).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$HERE/templates/go-component"
MIT="$HERE/../../asgard/LICENSES/MIT.txt"   # the side-by-side asgard clone holds the MIT text
# Bump through a reviewed PR. The image must be at least two weeks old when pinned.
GO_IMAGE="docker.io/library/golang:1.26.7-bookworm@sha256:e8c859f5632dcfde7b32d2012b4351728f6437930887c2f6a91ea242459e5514"
SPEC="https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md"
die() { echo "scaffold-component: $*" >&2; exit 2; }
shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2+: keep & in the job sentence literal

mit=false
if [ "${1:-}" = --mit-templates ]; then mit=true; shift; fi
[ $# = 3 ] || die 'usage: scaffold-component.sh [--mit-templates] <repo> "<job sentence>" <clone dir>'
r="$1"; job="$2"; d="$3"
[[ "$r" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "bad repo name: $r"
[ -n "$job" ] || die "the job sentence is empty"
[ -d "$d/.git" ] && [ -f "$d/REUSE.toml" ] && [ -f "$d/LICENSES/AGPL-3.0-only.txt" ] \
  || die "$d doesn't hold create-repo.sh's first commit"
if [[ "$r" == *-* ]]; then title="$r"; else title="${r^}"; fi

# template -> destination
FILES=(go.mod.tmpl:go.mod README.md.tmpl:README.md AGENTS.md.tmpl:AGENTS.md
  architecture.md.tmpl:docs/architecture.md devcontainer.json.tmpl:.devcontainer/devcontainer.json
  gitignore.tmpl:.gitignore pre-commit-config.yaml.tmpl:.pre-commit-config.yaml)
$mit && FILES+=(templates-README.md.tmpl:templates/README.md)
for f in "${FILES[@]}"; do [ ! -e "$d/${f#*:}" ] || die "$d/${f#*:} exists; nothing was written"; done
if $mit; then
  [ ! -e "$d/LICENSES/MIT.txt" ] || die "$d/LICENSES/MIT.txt exists; nothing was written"
  [ -f "$MIT" ] || die "no MIT text at $MIT"
fi

render() { # render TEMPLATE: prints it with the markers filled; the job goes last, so its own text stays as is
  local s; s="$(cat "$TPL/$1")"
  s="${s//\{\{REPO\}\}/$r}"; s="${s//\{\{TITLE\}\}/$title}"; s="${s//\{\{DATE\}\}/$(date +%F)}"
  s="${s//\{\{SPEC\}\}/$SPEC}"; s="${s//\{\{GO_IMAGE\}\}/$GO_IMAGE}"; s="${s//\{\{JOB\}\}/$job}"
  printf '%s\n' "$s"
}
for f in "${FILES[@]}"; do
  mkdir -p "$(dirname "$d/${f#*:}")"
  render "${f%%:*}" > "$d/${f#*:}"
done
if $mit; then
  cp "$MIT" "$d/LICENSES/MIT.txt"
  cat >> "$d/REUSE.toml" <<'EOF'

[[annotations]]
path = ["templates/**"]
precedence = "closest"
SPDX-FileCopyrightText = "2026 Bruno Guilhermo de Barros Valério"
SPDX-License-Identifier = "MIT"
EOF
fi
echo "Scaffolded $r in $d."
echo "Next: write the Responsibilities and Depends on sections of docs/architecture.md from the spec,"
echo "then commit on a branch and open a PR through as-bot.sh."

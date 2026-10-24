#!/usr/bin/env bash
# Tests for repo-config.sh, the per-org config loader.   scripts/tests/repo-config.test.sh
# shellcheck disable=SC1091,SC2329  # the library is sourced by path; refused() is called by check
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }

# load ARGS...: source the library, parse ARGS, load, and print every variable, one per line.
load() {
  ( . "$HERE/../repo-config.sh"
    repo_config_args "$@"
    repo_config_load
    printf '%s\n' "ORG=$RC_ORG" "LIC=$RC_LICENCE" "DLIC=$RC_DOCS_LICENCE" "PATHS=$RC_DOCS_PATHS" \
      "CR=$RC_COPYRIGHT" "DIR=$RC_LICENCE_DIR" "ISSUES=$RC_ISSUES_ON" "CI=$RC_CI" )
}
# refused ARGS...: exit 2, and stderr starts with "repo-config:".
refused() {
  local err rc
  err="$(load "$@" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = 2 ] && [[ "$err" == repo-config:* ]]
}
# cfg NAME JSON: write $T/NAME.json.
cfg() { printf '%s\n' "$2" > "$T/$1.json"; }
base='"org": "acme", "licence": "MIT", "copyright": "Acme"'

out="$(load --org ouroboric-dev)"
check "ouroboric-dev loads" bash -c "[ \"\$1\" = \"\$2\" ]" _ "$out" "ORG=ouroboric-dev
LIC=AGPL-3.0-only
DLIC=CC-BY-4.0
PATHS=\"docs/**\", \"README.md\", \"AGENTS.md\"
CR=Bruno Guilhermo de Barros Valério
DIR=$(cd "$HERE/../../LICENSES" && pwd)
ISSUES= yggdrasil asgard 
CI=reuse,markdown,actions"
check "licence_dir is the umbrella's LICENSES" \
  [ "$(load --org ouroboric-dev | sed -n 's/^DIR=//p')" = "$(cd "$HERE/../../LICENSES" && pwd)" ]
check "the holder keeps its accent" \
  [ "$(load --org ouroboric-dev | sed -n 's/^CR=//p')" = 'Bruno Guilhermo de Barros Valério' ]
check "after_create fills the repo" \
  [ "$( . "$HERE/../repo-config.sh"; repo_config_args --org ouroboric-dev; repo_config_load; repo_after_create public alpha)" = \
    'Add alpha to the pr-bot: https://github.com/organizations/ouroboric-dev/settings/installations, ouroboric-pr-bot, Configure, Repository access.' ]
check "after_create private fills the repo" \
  [ "$( . "$HERE/../repo-config.sh"; repo_config_args --org ouroboric-dev; repo_config_load; repo_after_create private beta)" = \
    'Never add beta to the pr-bot: agents must not see this repo.' ]
check "no after_create prints nothing" bash -c "
  echo '{$base}' > '$T/min.json'
  [ -z \"\$( . '$HERE/../repo-config.sh'; repo_config_args --config '$T/min.json'; repo_config_load; repo_after_create public x)\" ]"
check "RC_REST and RC_FROM are set" bash -c "
  . '$HERE/../repo-config.sh'; cd '$T'; repo_config_args --config min.json a b
  [ \"\${RC_REST[*]}\" = 'a b' ] && [ \"\${RC_FROM[*]}\" = \"--config $T/min.json\" ] && [ \"\$RC_FILE\" = '$T/min.json' ]"
check "a minimal config loads with empty defaults" bash -c "
  . '$HERE/../repo-config.sh'; repo_config_args --config '$T/min.json'; repo_config_load
  [ -z \"\$RC_DOCS_LICENCE\$RC_LICENCE_DIR\$RC_ISSUES_ON\" ] && [ -z \"\$RC_CI\" ]"

check "no --org or --config is refused" refused
cfg m '{"org": "acme", "licence": "MIT"}'
check "a missing copyright is refused" refused --config "$T/m.json"
cfg m '{"licence": "MIT", "copyright": "Acme"}'
check "a missing org is refused" refused --config "$T/m.json"
cfg m "{$base, \"colour\": \"red\"}"
check "an unknown key is refused" refused --config "$T/m.json"
cfg m "{$base, \"docs_licence\": \"CC-BY-4.0\"}"
check "docs_licence without docs_paths is refused" refused --config "$T/m.json"
cfg m "{$base, \"docs_paths\": [\"docs/**\"]}"
check "docs_paths without docs_licence is refused" refused --config "$T/m.json"
cfg m "{$base, \"docs_licence\": \"CC-BY-4.0\", \"docs_paths\": []}"
check "empty docs_paths is refused" refused --config "$T/m.json"
cfg m "{$base, \"docs_licence\": \"CC-BY-4.0\", \"docs_paths\": [\"a\\\\\\\\b\"]}"
check "a backslash in a docs path is refused" refused --config "$T/m.json"
cfg m '{"org": "acme", "licence": "MIT", "copyright": "Ac\"me"}'
check "a quote in copyright is refused" refused --config "$T/m.json"
cfg m '{"org": "acme", "licence": "MIT", "copyright": ""}'
check "an empty copyright is refused" refused --config "$T/m.json"
cfg m '{"org": "-acme", "licence": "MIT", "copyright": "Acme"}'
check "a bad org name is refused" refused --config "$T/m.json"
cfg m '{"org": "acme", "licence": "M IT", "copyright": "Acme"}'
check "a bad licence is refused" refused --config "$T/m.json"
cfg m "{$base, \"issues_on\": [\"ok\", \"bad name\"]}"
check "a bad issues_on name is refused" refused --config "$T/m.json"
cfg m "{$base, \"ci\": [\"Reuse\"]}"
check "a bad ci name is refused" refused --config "$T/m.json"
cfg m "{$base, \"after_create\": {\"other\": \"x\"}}"
check "an unknown after_create key is refused" refused --config "$T/m.json"
echo '{not json' > "$T/m.json"
check "invalid JSON is refused" refused --config "$T/m.json"
printf '%s\n%s\n' "{$base}" "{$base}" > "$T/m.json"
check "two JSON documents in one file are refused" refused --config "$T/m.json"
echo '[1]' > "$T/m.json"
check "a JSON array is refused" refused --config "$T/m.json"
check "a missing file is refused" refused --config "$T/nope.json"
cfg other '{"org": "other", "licence": "MIT", "copyright": "Acme"}'
mkdir -p "$T/orgs"; cp "$T/other.json" "$T/orgs/acme.json"
REPO_ORGS_DIR="$T/orgs" check "an org that differs from --org is refused" refused --org acme
check "a bad --org name is refused" refused --org '../x'
check "--org with a missing file is refused" refused --org nonesuch
check "--org plus --config is refused" refused --org ouroboric-dev --config "$T/min.json"
check "--config plus --org is refused" refused --config "$T/min.json" --org ouroboric-dev
check "--org twice is refused" refused --org ouroboric-dev --org ouroboric-dev
check "--config twice is refused" refused --config "$T/min.json" --config "$T/min.json"
cfg m "{$base, \"licence_dir\": \"nowhere\"}"
check "a licence_dir that does not exist is refused" refused --config "$T/m.json"

mkdir -p "$T/my org/lic"
printf '%s\n' "{$base, \"licence_dir\": \"lic\"}" > "$T/my org/acme.json"
check "a config in a folder with a space" \
  [ "$(load --config "$T/my org/acme.json" | sed -n 's/^DIR=//p')" = "$T/my org/lic" ]
check "a relative --config gives an absolute RC_FILE" bash -c "
  cd '$T/my org' && . '$HERE/../repo-config.sh' && repo_config_args --config acme.json && [ \"\$RC_FILE\" = '$T/my org/acme.json' ]"

# owner: the account is an org (the default) or a user.
owner() { ( . "$HERE/../repo-config.sh"; repo_config_args "$@"; repo_config_load; printf '%s' "$RC_OWNER" ); }
check "without owner, the account is an org" [ "$(owner --config "$T/min.json")" = org ]
check "ouroboric-dev is an org" [ "$(owner --org ouroboric-dev)" = org ]
cfg u "{$base, \"owner\": \"user\"}"
check "owner user loads" [ "$(owner --config "$T/u.json")" = user ]
cfg m "{$base, \"owner\": \"team\"}"
check "an unknown owner is refused" refused --config "$T/m.json"
cfg m "{$base, \"owner\": 1}"
check "an owner that is not a string is refused" refused --config "$T/m.json"
check "the user example is a user, with its licence text and no docs licence" bash -c "
  . '$HERE/../repo-config.sh'; repo_config_args --config '$HERE/../orgs/examples/user.json'; repo_config_load
  [ \"\$RC_OWNER\" = user ] && [ -s \"\$RC_LICENCE_DIR/\$RC_LICENCE.txt\" ] && [ -z \"\$RC_DOCS_LICENCE\" ]"

# An operator's own config lives in orgs/local/, which git ignores; --org finds it there.
mkdir -p "$T/o/local"
printf '%s\n' '{"org": "someone", "owner": "user", "licence": "MIT", "copyright": "Someone"}' > "$T/o/local/someone.json"
check "--org finds an operator's config in local/" bash -c "
  . '$HERE/../repo-config.sh'; REPO_ORGS_DIR='$T/o' repo_config_args --org someone; repo_config_load
  [ \"\$RC_FILE\" = '$T/o/local/someone.json' ] && [ \"\$RC_OWNER\" = user ]"
cp "$T/o/local/someone.json" "$T/o/someone.json"
REPO_ORGS_DIR="$T/o" check "a name in both orgs/ and local/ is refused" refused --org someone
REPO_ORGS_DIR="$T/o" check "a name in neither is refused" refused --org nobody
check "git ignores the operator configs in local/" git -C "$HERE/../.." check-ignore -q scripts/orgs/local/someone.json
check "git ignores an operator's licence texts in local/" git -C "$HERE/../.." check-ignore -q scripts/orgs/local/someone/LicenseRef-Proprietary.txt
check "git keeps local/README.md" bash -c "! git -C '$HERE/../..' check-ignore -q scripts/orgs/local/README.md"
check "no operator config is committed: every committed config is an org's or an example" \
  bash -c "[ -z \"\$(git -C '$HERE/../..' ls-files 'scripts/orgs/*.json' 'scripts/orgs/local/*' | grep -vx -e 'scripts/orgs/ouroboric-dev.json' -e 'scripts/orgs/examples/user.json' -e 'scripts/orgs/local/README.md')\" ]"
exit $fail

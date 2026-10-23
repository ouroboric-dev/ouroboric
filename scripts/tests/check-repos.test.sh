#!/usr/bin/env bash
# Tests for check-repos.sh's ruleset check against a fake gh.   scripts/tests/check-repos.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
mkdir -p "$T/bin" "$T/GET" && cp "$HERE/fake-gh" "$T/bin/gh" && chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" FAKE_GH_DIR="$T"
STD='{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true,"require_last_push_approval":true}}'
CHECK='{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"test","integration_id":15368}]}}'
OTHER='{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"test","integration_id":999}]}}'
LINT='{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"lint","integration_id":15368}]}}'
BOTH='{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"test","integration_id":15368},{"context":"lint","integration_id":15368}]}}'
# repo <name> <workflows: none|lint|ci|both> <rules json>
repo() {
  echo '[{"id":1,"name":"protect-main","enforcement":"active"}]' > "$T/GET/repos_ouroboric-dev_$1_rulesets.json"
  echo "{\"rules\":[$3]}" > "$T/GET/repos_ouroboric-dev_$1_rulesets_1.json"
  case "$2" in lint|both) echo '{"name":"lint.yml"}' > "$T/GET/repos_ouroboric-dev_$1_contents_.github_workflows_lint.yml.json" ;; esac
  case "$2" in ci|both) echo '{"name":"ci.yml"}' > "$T/GET/repos_ouroboric-dev_$1_contents_.github_workflows_ci.yml.json" ;; esac
  return 0
}
result() { "$HERE/../check-repos.sh" --check ruleset "$1" | cut -d' ' -f1; }

repo plain none "$STD";              check "no CI, standard rules: PASS" [ "$(result plain)" = PASS ]
repo unrequired ci "$STD";        check "CI, but its check isn't required: FAIL" [ "$(result unrequired)" = FAIL ]
repo required ci "$STD,$CHECK";   check "CI, and test from GitHub Actions is required: PASS" [ "$(result required)" = PASS ]
repo spoofable ci "$STD,$OTHER";  check "CI, but another app can satisfy the check: FAIL" [ "$(result spoofable)" = FAIL ]
repo stray none "$STD,$CHECK";       check "a required check with no CI to pass it: FAIL" [ "$(result stray)" = FAIL ]
repo lintreq lint "$STD,$LINT";    check "lint.yml, and lint is required: PASS" [ "$(result lintreq)" = PASS ]
repo bothreq both "$STD,$BOTH";    check "both workflows, lint and test required (any order): PASS" [ "$(result bothreq)" = PASS ]
repo lintmiss lint "$STD";         check "lint.yml, but lint is not required: FAIL" [ "$(result lintmiss)" = FAIL ]
repo lintstray none "$STD,$LINT";  check "lint required with no lint.yml: FAIL" [ "$(result lintstray)" = FAIL ]
# settings: a factory repo passes only with issues on, any other repo only with issues off.
# The fake answers the GraphQL query with one canned reply per FAKE_GH_DIR.
settings_result() { # <repo> <hasIssuesEnabled>
  local d; d="$(mktemp -d -p "$T")"; mkdir -p "$d/GET"
  echo "{\"data\":{\"repository\":{\"visibility\":\"PUBLIC\",\"hasIssuesEnabled\":$2,\"hasWikiEnabled\":false,\"mergeCommitAllowed\":false,\"rebaseMergeAllowed\":false}}}" > "$d/GET/graphql.json"
  FAKE_GH_DIR="$d" "$HERE/../check-repos.sh" --check settings "$1" | cut -d' ' -f1
}
check "settings, factory repo with issues on: PASS" [ "$(settings_result yggdrasil true)" = PASS ]
check "settings, factory repo with issues off: FAIL" [ "$(settings_result asgard false)" = FAIL ]
check "settings, other repo with issues off: PASS" [ "$(settings_result gungnir false)" = PASS ]
check "settings, other repo with issues on: FAIL" [ "$(settings_result ouroboric true)" = FAIL ]
# shared: the realms carry one copy of each shared script, and helheim-go's is the source.
# A fixture umbrella: <helheim-go docs.sh|-> <midgard-react docs.sh|-|nodir> [<helheim-go protected-common|->] [<midgard-react protected-common|->]
# protected-common defaults to the same content in both realms; "-" leaves it out.
F=devcontainer/checks/docs.sh
PC=devcontainer/checks/protected-common
shared_root() {
  local d; d="$(mktemp -d -p "$T")"
  mkdir -p "$d/yggdrasil/helheim-go/devcontainer/checks"
  [ "$1" = - ] || printf '%s\n' "$1" > "$d/yggdrasil/helheim-go/$F"
  [ "${3-pc}" = - ] || printf '%s\n' "${3-pc}" > "$d/yggdrasil/helheim-go/$PC"
  if [ "$2" != nodir ]; then
    mkdir -p "$d/yggdrasil/midgard-react/devcontainer/checks"
    [ "$2" = - ] || printf '%s\n' "$2" > "$d/yggdrasil/midgard-react/$F"
    [ "${4-pc}" = - ] || printf '%s\n' "${4-pc}" > "$d/yggdrasil/midgard-react/$PC"
  fi
  echo "$d"
}
shared() { CHECK_REPOS_ROOT="$1" "$HERE/../check-repos.sh" --check shared "$2"; }
r="$(shared_root same same)"
check "shared, same file in both realms: PASS" [ "$(shared "$r" midgard-react)" = "PASS midgard-react shared" ]
check "shared, helheim-go against itself: PASS" [ "$(shared "$r" helheim-go)" = "PASS helheim-go shared" ]
r="$(shared_root same other)"
check "shared, one byte different: FAIL naming docs.sh" [ "$(shared "$r" midgard-react)" = "FAIL midgard-react shared: $F differs from helheim-go's" ]
r="$(shared_root same same pc other)"
check "shared, protected-common differs: FAIL naming protected-common" [ "$(shared "$r" midgard-react)" = "FAIL midgard-react shared: $PC differs from helheim-go's" ]
r="$(shared_root same same pc -)"
check "shared, protected-common missing in midgard-react: FAIL naming the path" [ "$(shared "$r" midgard-react)" = "FAIL midgard-react shared: $r/yggdrasil/midgard-react/$PC is missing" ]
r="$(shared_root same -)"
check "shared, file missing in midgard-react: FAIL naming the path" [ "$(shared "$r" midgard-react)" = "FAIL midgard-react shared: $r/yggdrasil/midgard-react/$F is missing" ]
r="$(shared_root same nodir)"
check "shared, midgard-react not checked out: FAIL naming the path" [ "$(shared "$r" midgard-react)" = "FAIL midgard-react shared: $r/yggdrasil/midgard-react/$F is missing" ]
check "shared, not a realm: PASS" [ "$(shared "$r" gungnir)" = "PASS gungnir shared: not a realm" ]
r="$(shared_root - same)"
check "shared, helheim-go's source missing: FAIL for midgard-react" [ "$(shared "$r" midgard-react)" = "FAIL midgard-react shared: $r/yggdrasil/helheim-go/$F is missing" ]
check "shared, helheim-go's source missing: FAIL for helheim-go" [ "$(shared "$r" helheim-go)" = "FAIL helheim-go shared: $r/yggdrasil/helheim-go/$F is missing" ]
# A hash that can't be computed must fail closed, not compare equal as two empty strings.
mkdir -p "$T/nohash" && printf '#!/bin/sh\nexit 1\n' > "$T/nohash/sha256sum" && chmod +x "$T/nohash/sha256sum"
r="$(shared_root same same)"
check "shared, sha256sum fails: FAIL naming the file" [ "$(PATH="$T/nohash:$PATH" shared "$r" midgard-react)" = "FAIL midgard-react shared: can't read $r/yggdrasil/helheim-go/$F" ]
# agents: voluspa is a leaf, so it lives at <root>/yggdrasil/voluspa and must link the yggdrasil invariants.
mkdir -p "$T/vroot/yggdrasil/voluspa"
printf '# AGENTS.md: Voluspa\n\nInvariants: https://github.com/ouroboric-dev/yggdrasil/blob/main/AGENTS.md#invariants\n' > "$T/vroot/yggdrasil/voluspa/AGENTS.md"
check "agents, voluspa is a leaf under yggdrasil: PASS" [ "$(CHECK_REPOS_ROOT="$T/vroot" "$HERE/../check-repos.sh" --check agents voluspa)" = "PASS voluspa agents" ]
# services: the services' versions live in niflheim-local's pack; mimir's Dockerfile and helheim-go's template CI copy them.
# A fixture root; each argument overrides a part: seaweed=<digest> pgci=<image> pgpkg=<package> shape=folded|inline|nopkg, and drop=<repo> leaves a clone out.
PGIMG=docker.io/library/postgres:18.4-bookworm@sha256:882236b897e39051d2368c5ccc6cda944904723506b2dfc97f2a8f5bc9afa382
SWD=sha256:fc9f76fa993ad69966ffeb2f65d0318fcae39c6f8e20cf68ef7b3a5cb97769e5
services_root() {
  local d seaweed="$SWD" pgci="$PGIMG" pgpkg="postgresql-18=18.4-1.pgdg120+1" shape=folded drop="" weedfmt=plain a
  for a in "$@"; do case "$a" in seaweed=*) seaweed="${a#*=}" ;; pgci=*) pgci="${a#*=}" ;; pgpkg=*) pgpkg="${a#*=}" ;; shape=*) shape="${a#*=}" ;; drop=*) drop="${a#*=}" ;; weedfmt=*) weedfmt="${a#*=}" ;; esac; done
  d="$(mktemp -d -p "$T")"
  mkdir -p "$d/yggdrasil/niflheim-local" "$d/yggdrasil/helheim-go/templates/api/.github/workflows" "$d/mimir/client-gallery-lite/environment"
  { printf 'services:\n  postgres:\n'
    if [ "$shape" = folded ]; then printf '    image: >-\n      %s\n' "$PGIMG"; else printf '    image: %s\n' "$PGIMG"; fi
    printf '    env:\n      POSTGRES_DB: app\n  s3:\n    image: docker.io/chrislusf/seaweedfs:4.45@%s\n    ports: [8333]\n' "$SWD"
  } > "$d/yggdrasil/niflheim-local/pack.yaml"
  { printf 'jobs:\n  test:\n    services:\n      postgres:\n        image: >-\n          %s\n        env:\n          POSTGRES_DB: app\n' "$pgci"
  } > "$d/yggdrasil/helheim-go/templates/api/.github/workflows/ci.yml"
  local from=FROM as=AS flag=""
  [ "$weedfmt" != lower ] || { from=from; as=as; }
  [ "$weedfmt" != flag ] || flag="--platform=linux/amd64 "
  { printf '%s %sdocker.io/chrislusf/seaweedfs:4.45@%s %s weed\nFROM mcr.microsoft.com/playwright:v1.63.0-noble@sha256:eff1\n' "$from" "$flag" "$seaweed" "$as"
    if [ "$shape" = nopkg ]; then printf 'RUN apt-get install -y postgresql-18\n'; else printf 'RUN apt-get install -y --no-install-recommends \\\n    %s \\\n    git\n' "$pgpkg"; fi
  } > "$d/mimir/client-gallery-lite/environment/Dockerfile"
  case "$drop" in mimir) rm -rf "$d/mimir" ;; helheim-go|niflheim-local) rm -rf "$d/yggdrasil/$drop" ;; esac
  echo "$d"
}
# shellcheck disable=SC2053  # the pattern is meant as a glob
matches() { [[ "$1" == $2 ]]; }   # <text> <glob pattern>
services() { CHECK_REPOS_ROOT="$1" "$HERE/../check-repos.sh" --check services "${@:2}"; }
r="$(services_root)"
check "services, the copies agree: PASS" [ "$(services "$r" | cut -d' ' -f1 | sort -u)" = PASS ]
check "services, prints both Postgres minors" matches "$(services "$r")" "*18.4*18.4*"
r="$(services_root shape=inline)"
check "services, an inline image line: PASS" [ "$(services "$r" | cut -d' ' -f1 | sort -u)" = PASS ]
r="$(services_root seaweed=sha256:0000)"
out="$(services "$r")"
check "services, another weed digest: FAIL naming the Dockerfile and both digests" matches "$out" "*FAIL*client-gallery-lite/environment/Dockerfile*sha256:0000*$SWD*"
r="$(services_root pgci=docker.io/library/postgres:18.4-bookworm@sha256:0000)"
out="$(services "$r")"
check "services, another CI image: FAIL naming ci.yml and both images" matches "$out" "*FAIL*ci.yml*sha256:0000*$PGIMG*"
r="$(services_root pgpkg=postgresql-17=17.4-1)"
out="$(services "$r")"
check "services, another major: FAIL naming the Dockerfile and both majors" matches "$out" "*FAIL*Dockerfile*17*18*"
r="$(services_root shape=nopkg)"
out="$(services "$r")"
check "services, an unpinned package: FAIL" matches "$out" "*FAIL*Dockerfile*pinned*"
r="$(services_root weedfmt=lower)"
check "services, a lower-case as: PASS" [ "$(services "$r" | cut -d' ' -f1 | sort -u)" = PASS ]
r="$(services_root weedfmt=flag)"
check "services, FROM --platform=... IMAGE AS weed: PASS" [ "$(services "$r" | cut -d' ' -f1 | sort -u)" = PASS ]
r="$(services_root pgpkg="postgresql-18=\${PGV}")"
out="$(services "$r")"
check "services, an ARG-based pin: FAIL, pin the literal version" matches "$out" "*FAIL*Dockerfile*pin the literal version*" 
r="$(services_root pgpkg=postgresql-18=18.5-1.pgdg120+1)"
out="$(services "$r"; echo "exit $?")"
check "services, another minor: PASS with a line that says so" matches "$out" "*minor*18.4*18.5*exit 0" && ! matches "$out" "*FAIL*"
for m in niflheim-local helheim-go mimir; do
  r="$(services_root drop=$m)"
  out="$(services "$r")"
  check "services, no $m clone: FAIL naming the path" matches "$out" "*FAIL*$m*" && ! matches "$out" "*PASS*"
done
r="$(services_root)"
check "services, once per call whatever repos are named" [ "$(services "$r" ouroboric yggdrasil gungnir | grep -c 'services')" = "$(services "$r" | grep -c 'services')" ]
out="$(CHECK_REPOS_ROOT="$r" "$HERE/../check-repos.sh" --check agents gungnir 2>&1)"
check "services, not in the default checks" [ "$(grep -c '^\(FAIL\|PASS\) niflheim-local services' <<<"$out")" = 0 ]
check "services, the check never names the hidden suites" [ -z "$(grep -n 'hidden-suites\|huldra\|credentials\|factory.env' <(sed -n '/^check_services/,/^}/p' "$HERE/../check-repos.sh"))" ]
exit $fail

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
# A fixture umbrella: <helheim-go file content|-> <midgard-react file content|-|nodir>
F=devcontainer/checks/docs.sh
shared_root() {
  local d; d="$(mktemp -d -p "$T")"
  mkdir -p "$d/yggdrasil/helheim-go/devcontainer/checks"
  [ "$1" = - ] || printf '%s\n' "$1" > "$d/yggdrasil/helheim-go/$F"
  if [ "$2" != nodir ]; then
    mkdir -p "$d/yggdrasil/midgard-react/devcontainer/checks"
    [ "$2" = - ] || printf '%s\n' "$2" > "$d/yggdrasil/midgard-react/$F"
  fi
  echo "$d"
}
shared() { CHECK_REPOS_ROOT="$1" "$HERE/../check-repos.sh" --check shared "$2"; }
r="$(shared_root same same)"
check "shared, same file in both realms: PASS" [ "$(shared "$r" midgard-react)" = "PASS midgard-react shared" ]
check "shared, helheim-go against itself: PASS" [ "$(shared "$r" helheim-go)" = "PASS helheim-go shared" ]
r="$(shared_root same other)"
check "shared, one byte different: FAIL naming docs.sh" [ "$(shared "$r" midgard-react)" = "FAIL midgard-react shared: $F differs from helheim-go's" ]
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
exit $fail

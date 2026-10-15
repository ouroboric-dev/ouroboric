#!/usr/bin/env bash
# Tests for setup-repo.sh's ruleset against a fake gh.   scripts/tests/setup-repo.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }
mkdir -p "$T/bin" && cp "$HERE/fake-gh" "$T/bin/gh" && chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"
G='repos_ouroboric-dev'
# ruleset_body <repo>: the body of the last ruleset write
ruleset_body() { jq -rs "map(select(.path|test(\"repos/ouroboric-dev/$1/rulesets\")))|last|.body" "$FAKE_GH_DIR/log"; }
has_check() { jq -e '[.rules[]|select(.type=="required_status_checks")|.parameters
  |select(.strict_required_status_checks_policy==true)|.required_status_checks[]
  |select(.context=="test" and .integration_id==15368)]|length==1' >/dev/null; }
export -f ruleset_body has_check

export FAKE_GH_DIR="$T/no-ci"; mkdir -p "$FAKE_GH_DIR/GET"
echo '[]' > "$FAKE_GH_DIR/GET/${G}_alpha_rulesets.json"
GH_TOKEN=fake "$HERE/../setup-repo.sh" alpha > /dev/null
check "a repo without CI: the ruleset is created" bash -c "jq -e 'select(.method==\"POST\" and .path==\"repos/ouroboric-dev/alpha/rulesets\")' '$FAKE_GH_DIR/log' >/dev/null"
check "a repo without CI: the standard rules and no required check" bash -c "ruleset_body alpha | jq -e '[.rules[].type]|sort==[\"deletion\",\"non_fast_forward\",\"pull_request\"]' >/dev/null"

export FAKE_GH_DIR="$T/ci"; mkdir -p "$FAKE_GH_DIR/GET"
echo '[{"id":7,"name":"protect-main"}]' > "$FAKE_GH_DIR/GET/${G}_beta_rulesets.json"
echo '{"name":"ci.yml"}' > "$FAKE_GH_DIR/GET/${G}_beta_contents_.github_workflows_ci.yml.json"
GH_TOKEN=fake "$HERE/../setup-repo.sh" beta > /dev/null
check "a repo with CI: the existing ruleset is replaced" bash -c "jq -e 'select(.method==\"PUT\" and .path==\"repos/ouroboric-dev/beta/rulesets/7\")' '$FAKE_GH_DIR/log' >/dev/null"
check "a repo with CI: test from GitHub Actions is required, on an up-to-date branch" bash -c "ruleset_body beta | has_check"
check "the other rules stay" bash -c "ruleset_body beta | jq -e '[.rules[].type]|sort==[\"deletion\",\"non_fast_forward\",\"pull_request\",\"required_status_checks\"]' >/dev/null"
exit $fail

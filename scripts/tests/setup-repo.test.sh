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
# has_checks <context>...: the one required_status_checks rule holds exactly these contexts, all from
# GitHub Actions (app 15368), on a strict branch
has_checks() { jq -e --arg want "$(printf '%s\n' "$@" | sort | paste -sd+ -)" '[.rules[]|select(.type=="required_status_checks")]
  |length==1 and (.[0].parameters|.strict_required_status_checks_policy==true
  and all(.required_status_checks[]; .integration_id==15368)
  and ([.required_status_checks[].context]|sort|join("+"))==$want)' >/dev/null; }
no_checks() { jq -e '[.rules[]|select(.type=="required_status_checks")]|length==0' >/dev/null; }
export -f ruleset_body has_checks no_checks

export FAKE_GH_DIR="$T/no-ci"; mkdir -p "$FAKE_GH_DIR/GET"
echo '[]' > "$FAKE_GH_DIR/GET/${G}_alpha_rulesets.json"
GH_TOKEN=fake "$HERE/../setup-repo.sh" --org ouroboric-dev alpha > /dev/null
check "a repo without CI: the ruleset is created" bash -c "jq -e 'select(.method==\"POST\" and .path==\"repos/ouroboric-dev/alpha/rulesets\")' '$FAKE_GH_DIR/log' >/dev/null"
check "a repo without CI: the standard rules and no required check" bash -c "ruleset_body alpha | jq -e '[.rules[].type]|sort==[\"deletion\",\"non_fast_forward\",\"pull_request\"]' >/dev/null"
check "a repo without CI: no required_status_checks rule" bash -c "ruleset_body alpha | no_checks"

export FAKE_GH_DIR="$T/ci"; mkdir -p "$FAKE_GH_DIR/GET"
echo '[{"id":7,"name":"protect-main"}]' > "$FAKE_GH_DIR/GET/${G}_beta_rulesets.json"
echo '{"name":"ci.yml"}' > "$FAKE_GH_DIR/GET/${G}_beta_contents_.github_workflows_ci.yml.json"
GH_TOKEN=fake "$HERE/../setup-repo.sh" --org ouroboric-dev beta > /dev/null
check "a repo with CI: the existing ruleset is replaced" bash -c "jq -e 'select(.method==\"PUT\" and .path==\"repos/ouroboric-dev/beta/rulesets/7\")' '$FAKE_GH_DIR/log' >/dev/null"
check "a repo with CI: test from GitHub Actions is required, on an up-to-date branch" bash -c "ruleset_body beta | has_checks test"
check "the other rules stay" bash -c "ruleset_body beta | jq -e '[.rules[].type]|sort==[\"deletion\",\"non_fast_forward\",\"pull_request\",\"required_status_checks\"]' >/dev/null"

export FAKE_GH_DIR="$T/lookup-fails"; mkdir -p "$FAKE_GH_DIR/GET" "$FAKE_GH_DIR/ERR"
echo '[{"id":9,"name":"protect-main"}]' > "$FAKE_GH_DIR/GET/${G}_gamma_rulesets.json"
echo 'Server Error (HTTP 500)' > "$FAKE_GH_DIR/ERR/${G}_gamma_contents_.github_workflows_ci.yml"
check "a failed CI lookup stops the script" bash -c "! GH_TOKEN=fake '$HERE/../setup-repo.sh' --org ouroboric-dev gamma >/dev/null 2>&1"
check "a failed CI lookup leaves the ruleset alone" bash -c "! grep -q rulesets '$FAKE_GH_DIR/log' 2>/dev/null"
# Issues are on for the factories only. issues_field <repo>: the has_issues value setup-repo.sh sent
issues_field() { jq -rs "map(select(.method==\"PATCH\" and .path==\"repos/ouroboric-dev/$1\"))|first|.fields[]|select(startswith(\"has_issues=\"))" "$FAKE_GH_DIR/log"; }
for r in yggdrasil asgard gungnir; do
  export FAKE_GH_DIR="$T/issues-$r"; mkdir -p "$FAKE_GH_DIR/GET"
  echo '[]' > "$FAKE_GH_DIR/GET/${G}_${r}_rulesets.json"
  GH_TOKEN=fake "$HERE/../setup-repo.sh" --org ouroboric-dev "$r" > /dev/null
done
export FAKE_GH_DIR="$T/issues-yggdrasil"
check "a factory repo (yggdrasil): issues on" [ "$(issues_field yggdrasil)" = has_issues=true ]
export FAKE_GH_DIR="$T/issues-asgard"
check "a factory repo (asgard): issues on" [ "$(issues_field asgard)" = has_issues=true ]
export FAKE_GH_DIR="$T/issues-gungnir"
check "another repo (gungnir): issues off" [ "$(issues_field gungnir)" = has_issues=false ]

# lint.yml maps to lint, ci.yml to test; each is required only when its file exists.
export FAKE_GH_DIR="$T/lint-only"; mkdir -p "$FAKE_GH_DIR/GET"
echo '[]' > "$FAKE_GH_DIR/GET/${G}_delta_rulesets.json"
echo '{"name":"lint.yml"}' > "$FAKE_GH_DIR/GET/${G}_delta_contents_.github_workflows_lint.yml.json"
GH_TOKEN=fake "$HERE/../setup-repo.sh" --org ouroboric-dev delta > /dev/null
check "lint only: lint alone is required" bash -c "ruleset_body delta | has_checks lint"

export FAKE_GH_DIR="$T/both"; mkdir -p "$FAKE_GH_DIR/GET"
echo '[]' > "$FAKE_GH_DIR/GET/${G}_epsilon_rulesets.json"
echo '{"name":"lint.yml"}' > "$FAKE_GH_DIR/GET/${G}_epsilon_contents_.github_workflows_lint.yml.json"
echo '{"name":"ci.yml"}' > "$FAKE_GH_DIR/GET/${G}_epsilon_contents_.github_workflows_ci.yml.json"
GH_TOKEN=fake "$HERE/../setup-repo.sh" --org ouroboric-dev epsilon > /dev/null
check "both workflows: lint and test are required, in one rule" bash -c "ruleset_body epsilon | has_checks lint test"
check "both workflows: lint comes first" bash -c "ruleset_body epsilon | jq -e '[.rules[]|select(.type==\"required_status_checks\")|.parameters.required_status_checks[].context]==[\"lint\",\"test\"]' >/dev/null"

export FAKE_GH_DIR="$T/lint-fails"; mkdir -p "$FAKE_GH_DIR/GET" "$FAKE_GH_DIR/ERR"
echo '[{"id":9,"name":"protect-main"}]' > "$FAKE_GH_DIR/GET/${G}_zeta_rulesets.json"
echo 'Server Error (HTTP 500)' > "$FAKE_GH_DIR/ERR/${G}_zeta_contents_.github_workflows_lint.yml"
check "a failed lint lookup stops the script" bash -c "! GH_TOKEN=fake '$HERE/../setup-repo.sh' --org ouroboric-dev zeta >/dev/null 2>&1"
check "a failed lint lookup leaves the ruleset alone" bash -c "! grep -q rulesets '$FAKE_GH_DIR/log' 2>/dev/null"

# Any org: --config with org acme writes to repos/acme/...
printf '%s\n' '{"org":"acme","licence":"MIT","copyright":"Acme"}' > "$T/acme.json"
export FAKE_GH_DIR="$T/acme"; mkdir -p "$FAKE_GH_DIR/GET"
echo '[]' > "$FAKE_GH_DIR/GET/repos_acme_widget_rulesets.json"
echo '{"name":"lint.yml"}' > "$FAKE_GH_DIR/GET/repos_acme_widget_contents_.github_workflows_lint.yml.json"
GH_TOKEN=fake "$HERE/../setup-repo.sh" --config "$T/acme.json" widget > /dev/null
check "--config acme: the settings PATCH goes to repos/acme/widget" bash -c "jq -e 'select(.method==\"PATCH\" and .path==\"repos/acme/widget\")' '$FAKE_GH_DIR/log' >/dev/null"
check "--config acme: the ruleset goes to repos/acme/widget" bash -c "jq -e 'select(.method==\"POST\" and .path==\"repos/acme/widget/rulesets\")' '$FAKE_GH_DIR/log' >/dev/null"
check "--config acme: nothing is written outside acme" bash -c "! jq -e 'select(.path|test(\"ouroboric-dev\"))' '$FAKE_GH_DIR/log' >/dev/null"
check "--config acme: issues off" bash -c "jq -e 'select(.method==\"PATCH\" and (.fields|any(.==\"has_issues=false\")))' '$FAKE_GH_DIR/log' >/dev/null"
check "no repo argument: exit 2" bash -c "GH_TOKEN=fake '$HERE/../setup-repo.sh' --org ouroboric-dev >/dev/null 2>&1; [ \$? = 2 ]"
check "two repo arguments: exit 2" bash -c "GH_TOKEN=fake '$HERE/../setup-repo.sh' --org ouroboric-dev a b >/dev/null 2>&1; [ \$? = 2 ]"
exit $fail

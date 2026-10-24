#!/usr/bin/env bash
# Tests for setup-repo.sh's ruleset against a fake gh.   scripts/tests/setup-repo.test.sh
# shellcheck disable=SC2329  # the helper functions are exported and called inside check's bash -c
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
export FAKE_GH_DIR="$T/option"; mkdir -p "$FAKE_GH_DIR/GET"
check "an unknown option: exit 2, and gh is never called" \
  bash -c "GH_TOKEN=fake '$HERE/../setup-repo.sh' --org ouroboric-dev --cl >/dev/null 2>&1; [ \$? = 2 ] && [ ! -s '$FAKE_GH_DIR/log' ]"
# owner user: no org to hold the Actions allowlist, so each repo holds it. GitHub offers no secret
# scanning or private vulnerability reporting on a user's private repo.
printf '%s\n' '{"org":"me","owner":"user","licence":"MIT","copyright":"Me"}' > "$T/me.json"
PINS="$(sed -n 's/^ *- uses: \([^ ]*\).*/\1/p' "$HERE/../templates/ci/lint.yml" | jq -Rnc '[inputs]')"
# user_repo <dir> <visibility>: a fake for repos/me/widget with no ruleset yet
user_repo() { export FAKE_GH_DIR="$T/$1"; mkdir -p "$FAKE_GH_DIR/GET" "$FAKE_GH_DIR/ERR"
  echo "{\"visibility\":\"$2\"}" > "$FAKE_GH_DIR/GET/repos_me_widget.json"
  echo '[]' > "$FAKE_GH_DIR/GET/repos_me_widget_rulesets.json"; }
# logged <jq filter>: some logged request matches
logged() { jq -e "select($1)" "$FAKE_GH_DIR/log" >/dev/null; }
allowlisted() { logged '.method=="PUT" and .path=="repos/me/widget/actions/permissions" and (.body|fromjson|.enabled==true and .allowed_actions=="selected")' &&
  jq -se --argjson pins "$PINS" 'map(select(.method=="PUT" and .path=="repos/me/widget/actions/permissions/selected-actions"))
    |length==1 and (.[0].body|fromjson|.patterns_allowed==$pins and .github_owned_allowed==false and .verified_allowed==false)' "$FAKE_GH_DIR/log" >/dev/null; }
export -f logged allowlisted
export PINS
check "lint.yml pins two actions, each by a full SHA" bash -c "jq -e 'length==2 and all(test(\"@[0-9a-f]{40}\$\"))' <<<'$PINS' >/dev/null"

user_repo user-private private
GH_TOKEN=fake "$HERE/../setup-repo.sh" --config "$T/me.json" widget > /dev/null 2> "$T/err"; rc=$?
check "a private user repo: exit 0" [ "$rc" = 0 ]
check "a private user repo: only lint.yml's pinned actions may run" allowlisted
check "a private user repo: no secret scanning request" bash -c "! logged '.body|test(\"secret_scanning\")'"
check "a private user repo: no private vulnerability reporting request" bash -c "! logged '.path|test(\"private-vulnerability-reporting\")'"
check "a private user repo: stderr names what GitHub doesn't offer" \
  bash -c "grep -q 'secret scanning' '$T/err' && grep -q 'vulnerability reporting' '$T/err'"
check "a private user repo: the same ruleset as an org's" \
  bash -c "jq -rs 'map(select(.path==\"repos/me/widget/rulesets\"))|last|.body' \"\$FAKE_GH_DIR/log\" \
    | jq -e '([.rules[].type]|sort)==[\"deletion\",\"non_fast_forward\",\"pull_request\"] and .bypass_actors==[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\",\"bypass_mode\":\"pull_request\"}]' >/dev/null"
check "a private user repo: the same merge settings as an org's" \
  logged '.method=="PATCH" and .path=="repos/me/widget" and (.fields|index("allow_squash_merge=true") and index("has_issues=false"))'

user_repo user-public public
GH_TOKEN=fake "$HERE/../setup-repo.sh" --config "$T/me.json" widget > /dev/null 2>&1
check "a public user repo: secret scanning and push protection" logged '.path=="repos/me/widget" and (.body|test("secret_scanning_push_protection"))'
check "a public user repo: private vulnerability reporting" logged '.method=="PUT" and .path=="repos/me/widget/private-vulnerability-reporting"'
check "a public user repo: only lint.yml's pinned actions may run" allowlisted

user_repo user-free private
echo 'Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' > "$FAKE_GH_DIR/ERR/POST_repos_me_widget_rulesets"
GH_TOKEN=fake "$HERE/../setup-repo.sh" --config "$T/me.json" widget > "$T/out" 2> "$T/err"; rc=$?
check "a refused ruleset: exit non-zero" [ "$rc" != 0 ]
check "a refused ruleset: stderr says main is not protected" grep -q 'main is not protected' "$T/err"
check "a refused ruleset on a private user repo: stderr names GitHub Pro" grep -q 'GitHub Pro' "$T/err"
check "a refused ruleset: it never says set up" bash -c "! grep -q 'set up' '$T/out'"
check "a refused ruleset: the Actions allowlist is already in place" allowlisted

export FAKE_GH_DIR="$T/acme"
check "an org repo: the Actions allowlist is the org's, so none is written" bash -c "! logged '.path|test(\"actions/permissions\")'"
exit $fail

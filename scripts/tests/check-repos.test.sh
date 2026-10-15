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
# repo <name> <has ci: yes|no> <rules json>
repo() {
  echo '[{"id":1,"name":"protect-main","enforcement":"active"}]' > "$T/GET/repos_ouroboric-dev_$1_rulesets.json"
  echo "{\"rules\":[$3]}" > "$T/GET/repos_ouroboric-dev_$1_rulesets_1.json"
  [ "$2" = yes ] && echo '{"name":"ci.yml"}' > "$T/GET/repos_ouroboric-dev_$1_contents_.github_workflows_ci.yml.json"
  return 0
}
result() { "$HERE/../check-repos.sh" --check ruleset "$1" | cut -d' ' -f1; }

repo plain no "$STD";              check "no CI, standard rules: PASS" [ "$(result plain)" = PASS ]
repo unrequired yes "$STD";        check "CI, but its check isn't required: FAIL" [ "$(result unrequired)" = FAIL ]
repo required yes "$STD,$CHECK";   check "CI, and test from GitHub Actions is required: PASS" [ "$(result required)" = PASS ]
repo spoofable yes "$STD,$OTHER";  check "CI, but another app can satisfy the check: FAIL" [ "$(result spoofable)" = FAIL ]
repo stray no "$STD,$CHECK";       check "a required check with no CI to pass it: FAIL" [ "$(result stray)" = FAIL ]
exit $fail

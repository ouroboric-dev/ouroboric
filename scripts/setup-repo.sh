#!/usr/bin/env bash
# Apply the required setup to an ouroboric-dev repo, fixing drift. Safe to run twice.
# Leaves Discussions alone: ouroboric uses them as its public channel.
# A push after approval dismisses the approval, and the last push needs approval from someone else,
# so the pr-bot can't land commits nobody reviewed.
# Founder-run: GH_TOKEN must hold the short-lived admin token (agents' tokens can't change settings).
#   GH_TOKEN=... setup-repo.sh <repo>
set -euo pipefail
R="repos/ouroboric-dev/${1:?usage: setup-repo.sh <repo>}"
gh_api() { env -u GITHUB_TOKEN gh api "$@"; }
gh_api -X PATCH "$R" -F has_issues=false -F has_wiki=false -F has_projects=false \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false -F delete_branch_on_merge=true >/dev/null
gh_api -X PATCH "$R" --input - >/dev/null <<'EOF'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
EOF
gh_api -X PUT "$R/private-vulnerability-reporting" --silent
RULESET='{"name":"protect-main","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
 "bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}],
 "rules":[{"type":"deletion"},{"type":"non_fast_forward"},
  {"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"dismiss_stale_reviews_on_push":true,"require_code_owner_review":false,"require_last_push_approval":true,"required_approving_review_count":1,"required_review_thread_resolution":false}}'
# A repo with CI requires its "test" job, reported by GitHub Actions (app 15368) so no other app can
# pass it, on a branch that is up to date with main. Only a 404 means "no CI": any other failure stops
# the script, so an error never drops the required check.
if ci_err="$(gh_api "$R/contents/.github/workflows/ci.yml" --silent 2>&1 >/dev/null)"; then
  RULESET+=',{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"do_not_enforce_on_create":false,"required_status_checks":[{"context":"test","integration_id":15368}]}}'
elif [[ "$ci_err" != *"HTTP 404"* ]]; then
  echo "setup-repo: can't tell whether ${1} has CI, so the ruleset is unchanged: $ci_err" >&2
  exit 1
fi
RULESET+=']}'
id="$(gh_api "$R/rulesets" -q '.[]|select(.name=="protect-main")|.id' | head -1)"
if [ -n "$id" ]; then gh_api -X PUT "$R/rulesets/$id" --input - >/dev/null <<<"$RULESET"
else gh_api -X POST "$R/rulesets" --input - >/dev/null <<<"$RULESET"; fi
echo "set up ${1}"

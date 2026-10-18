#!/usr/bin/env bash
# Apply the required setup to a repo in the org that a config names, fixing drift. Safe to run twice.
# Leaves Discussions alone: ouroboric uses them as its public channel.
# Issues are on for the repos in the config's issues_on and off for every other repo.
# The ruleset requires one check per workflow the repo has, from this map: lint.yml gives "lint" and
# ci.yml gives "test". A repo with neither workflow requires nothing.
# A push after approval dismisses the approval, and the last push needs approval from someone else,
# so the pr-bot can't land commits nobody reviewed.
# Founder-run: GH_TOKEN must hold the short-lived admin token (agents' tokens can't change settings).
#   GH_TOKEN=... setup-repo.sh (--org <name>|--config <path>) <repo>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "setup-repo: $*" >&2; exit 2; }
# shellcheck source=repo-config.sh
. "$HERE/repo-config.sh"
repo_config_args "$@"
repo_config_load
[ ${#RC_REST[@]} -eq 1 ] || die "usage: setup-repo.sh (--org <name>|--config <path>) <repo>"
repo="${RC_REST[0]}"
R="repos/$RC_ORG/$repo"
gh_api() { env -u GITHUB_TOKEN gh api "$@"; }
if [[ "${RC_ISSUES_ON:-}" == *" $repo "* ]]; then ISSUES=true; else ISSUES=false; fi
gh_api -X PATCH "$R" -F has_issues=$ISSUES -F has_wiki=false -F has_projects=false \
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
# Look up both workflows before any write. Only a 404 means "no such workflow": any other failure stops
# the script, so an error never drops a required check.
checks=()
for pair in lint.yml:lint ci.yml:test; do
  if err="$(gh_api "$R/contents/.github/workflows/${pair%%:*}" --silent 2>&1 >/dev/null)"; then
    checks+=("${pair##*:}")
  elif [[ "$err" != *"HTTP 404"* ]]; then
    echo "setup-repo: can't tell whether ${repo} has ${pair%%:*}, so the ruleset is unchanged: $err" >&2
    exit 1
  fi
done
# The found jobs are required from GitHub Actions (app 15368) so no other app can pass them, on a branch
# that is up to date with main.
if [ ${#checks[@]} -gt 0 ]; then
  list="$(printf '%s\n' "${checks[@]}" | jq -Rn '[inputs|{context:.,integration_id:15368}]')"
  RULESET+=",$(jq -cn --argjson l "$list" '{type:"required_status_checks",parameters:{strict_required_status_checks_policy:true,do_not_enforce_on_create:false,required_status_checks:$l}}')"
fi
RULESET+=']}'
id="$(gh_api "$R/rulesets" -q '.[]|select(.name=="protect-main")|.id' | head -1)"
if [ -n "$id" ]; then gh_api -X PUT "$R/rulesets/$id" --input - >/dev/null <<<"$RULESET"
else gh_api -X POST "$R/rulesets" --input - >/dev/null <<<"$RULESET"; fi
echo "set up ${repo}"

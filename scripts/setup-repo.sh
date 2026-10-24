#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Apply the required setup to a repo in the org that a config names, fixing drift. Safe to run twice.
# Leaves Discussions alone: ouroboric uses them as its public channel.
# Issues are on for the repos in the config's issues_on and off for every other repo.
# The ruleset requires one check per workflow the repo has, from this map: lint.yml gives "lint" and
# ci.yml gives "test". A repo with neither workflow requires nothing.
# A push after approval dismisses the approval, and the last push needs approval from someone else,
# so the pr-bot can't land commits nobody reviewed.
# Auto-merge is on, so a pull request merges by itself once a human approves it and the required checks
# pass. It never skips the approval or a check: the ruleset still requires both.
# A user config ("owner": "user") gets the same setup, with two changes. Each repo holds its own Actions
# allowlist, lint.yml's pinned actions, because a user has no org to hold it. And a private repo gets no
# secret scanning, push protection or private vulnerability reporting, because GitHub offers none there.
# If GitHub refuses the ruleset, such as on a user's private repo without GitHub Pro, the script fails
# and says main is not protected, after every other setting is in place.
# Founder-run: GH_TOKEN must hold the short-lived admin token (agents' tokens can't change settings), or
# for a user config the user's own token with the same permissions.
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
case "$repo" in -*) die "unknown option: $repo" ;; esac
R="repos/$RC_ORG/$repo"
gh_api() { env -u GITHUB_TOKEN gh api "$@"; }
if [[ "${RC_ISSUES_ON:-}" == *" $repo "* ]]; then ISSUES=true; else ISSUES=false; fi
gh_api -X PATCH "$R" -F has_issues=$ISSUES -F has_wiki=false -F has_projects=false \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false -F allow_auto_merge=true \
  -F delete_branch_on_merge=true >/dev/null
visibility=''
[ "$RC_OWNER" != user ] || visibility="$(gh_api "$R" -q .visibility)"
if [ "$visibility" = private ]; then
  echo "setup-repo: $repo is a user's private repo, where GitHub offers no secret scanning, push protection or private vulnerability reporting: gitleaks in lint is the guard" >&2
else
  gh_api -X PATCH "$R" --input - >/dev/null <<'EOF'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
EOF
  gh_api -X PUT "$R/private-vulnerability-reporting" --silent
fi
# A user has no org to hold the Actions allowlist, so the repo holds it: lint.yml's actions at the SHAs
# it pins, and nothing else.
if [ "$RC_OWNER" = user ]; then
  pins="$(sed -n 's/^ *- uses: \([^ ]*\).*/\1/p' "$HERE/templates/ci/lint.yml" | jq -Rnc '[inputs]')"
  [ "$pins" != '[]' ] || die "templates/ci/lint.yml names no actions"
  gh_api -X PUT "$R/actions/permissions" --input - >/dev/null <<<'{"enabled":true,"allowed_actions":"selected"}'
  jq -cn --argjson p "$pins" '{github_owned_allowed:false,verified_allowed:false,patterns_allowed:$p}' \
    | gh_api -X PUT "$R/actions/permissions/selected-actions" --input - >/dev/null
fi
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
if [ -n "$id" ]; then write=(-X PUT "$R/rulesets/$id"); else write=(-X POST "$R/rulesets"); fi
if ! err="$(gh_api "${write[@]}" --input - <<<"$RULESET" 2>&1 >/dev/null)"; then
  echo "setup-repo: GitHub refused the ruleset, so main is not protected: $err" >&2
  if [ "$visibility" = private ] && [[ "$err" == *"HTTP 403"* ]]; then
    echo "setup-repo: a user's private repo needs GitHub Pro for rulesets. Upgrade, or make $repo public, then run setup-repo.sh again." >&2
  fi
  exit 1
fi
echo "set up ${repo}"

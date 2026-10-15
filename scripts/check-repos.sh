#!/usr/bin/env bash
# Check that ouroboric-dev repos have the required setup. See docs/4-ways-of-working/docs-standard.md.
#   check-repos.sh [--check settings|security|ruleset|reuse|agents|gitleaks|bot]... [repo...]
# The bot check also checks that the pr-bot can't reach any hidden repo. Run it under
# as-bot.sh --read all, because it reads the pr-bot's own list of repos.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # holds the side-by-side clones
ORG="ouroboric-dev"
UMBRELLAS=" ouroboric yggdrasil asgard "
LEAVES=" gungnir odin gleipnir jormungandr realm-web havamal "
LATER=" mimir "     # standard repos checked once they exist; side-by-side clones like the umbrellas
HIDDEN=" huldra "   # private repos that agents must never see
unset BOT_REPOS     # set only by bot_repos below, never from the environment
gh_api() { env -u GITHUB_TOKEN gh api "$@"; }
local_path() { if [[ "$LEAVES" == *" $1 "* ]]; then echo "$ROOT/yggdrasil/$1"; else echo "$ROOT/$1"; fi; }
fail=0
ok()  { echo "PASS $1 $2${3:+: $3}"; }
bad() { echo "FAIL $1 $2: $3"; fail=1; }

check_settings() { # GraphQL: REST hides the merge settings from tokens that can't push
  local v; v="$(gh_api graphql -f query="{repository(owner:\"$ORG\",name:\"$1\"){visibility hasIssuesEnabled hasWikiEnabled mergeCommitAllowed rebaseMergeAllowed}}" \
    -q '.data.repository|[.visibility,.hasIssuesEnabled,.hasWikiEnabled,.mergeCommitAllowed,.rebaseMergeAllowed]|map(tostring)|join(" ")')"
  [ "$v" = "PUBLIC false false false false" ] && ok "$1" settings || bad "$1" settings "got: $v (want public, no issues, no wiki, squash only)"
}
check_security() {
  local s p
  s="$(gh_api "repos/$ORG/$1" -q '[.security_and_analysis.secret_scanning.status,.security_and_analysis.secret_scanning_push_protection.status]|join(" ")')"
  p="$(gh_api "repos/$ORG/$1/private-vulnerability-reporting" -q .enabled)"
  [ "$s $p" = "enabled enabled true" ] && ok "$1" security || bad "$1" security "secret scanning, push protection, vuln reporting: $s $p"
}
check_ruleset() {
  local id rules
  id="$(gh_api "repos/$ORG/$1/rulesets" -q '.[]|select(.name=="protect-main" and .enforcement=="active")|.id' | head -1)"
  [ -n "$id" ] || { bad "$1" ruleset "no active protect-main ruleset"; return; }
  rules="$(gh_api "repos/$ORG/$1/rulesets/$id" -q '[.rules[]|.type+(if .type=="pull_request" then ":"+(.parameters.allowed_merge_methods|join("+"))+":"+(.parameters.required_approving_review_count|tostring)+(if .parameters.dismiss_stale_reviews_on_push then ":stale-dismissed" else "" end)+(if .parameters.require_last_push_approval then ":last-push-approved" else "" end) elif .type=="required_status_checks" then ":"+([.parameters.required_status_checks[]|.context+"@"+(.integration_id|tostring)]|join("+"))+(if .parameters.strict_required_status_checks_policy then ":strict" else "" end) else "" end)]|sort|join(",")')"
  local want="deletion,non_fast_forward,pull_request:squash:1:stale-dismissed:last-push-approved"
  # A repo with CI must require its test job from GitHub Actions (app 15368), on an up-to-date branch.
  gh_api "repos/$ORG/$1/contents/.github/workflows/ci.yml" --silent >/dev/null 2>&1 && want+=",required_status_checks:test@15368:strict"
  [ "$rules" = "$want" ] && ok "$1" ruleset || bad "$1" ruleset "rules: $rules (run setup-repo.sh)"
}
check_reuse() {
  local d; d="$(local_path "$1")"
  [ -d "$d" ] || { bad "$1" reuse "no local clone at $d"; return; }
  (cd "$d" && uvx -q --from 'reuse==5.0.2' reuse lint -q) && ok "$1" reuse || bad "$1" reuse "reuse lint failed"
}
check_agents() {
  local f; f="$(local_path "$1")/AGENTS.md"
  [ -f "$f" ] || { bad "$1" agents "no AGENTS.md"; return; }
  if [[ "$UMBRELLAS" == *" $1 "* ]]; then
    grep -q '^## Invariants' "$f" && ok "$1" agents || bad "$1" agents "umbrella AGENTS.md has no '## Invariants' section"
  elif [[ "$LEAVES" == *" $1 "* ]]; then
    local n; n="$(wc -l < "$f")"
    [ "$n" -le 120 ] || { bad "$1" agents "$n lines (keep it near 100)"; return; }
    grep -q '^## Invariants' "$f" && { bad "$1" agents "a leaf must not define its own invariants"; return; }
    grep -q 'ouroboric-dev/yggdrasil/blob/main/AGENTS.md#invariants' "$f" \
      && ok "$1" agents || bad "$1" agents "does not link the yggdrasil invariants"
  else
    ok "$1" agents "present"
  fi
}
check_gitleaks() {
  local f; f="$(local_path "$1")/.pre-commit-config.yaml"
  grep -q 'repo: https://github.com/gitleaks/gitleaks' "$f" 2>/dev/null && grep -q 'rev: v8.30.1' "$f" \
    && ok "$1" gitleaks || bad "$1" gitleaks "no pinned gitleaks pre-commit hook"
}

bot_repos() { # the pr-bot's installation repos, once; ERROR if they can't be listed
  [ -n "${BOT_REPOS+x}" ] && return
  local out
  # On an HTTP error gh prints the error body to stdout, so trust the exit status, not the output.
  out="$(gh_api installation/repositories --paginate -q '.repositories[].name' 2>/dev/null)" && [ -n "$out" ] \
    || { BOT_REPOS=ERROR; return; }
  BOT_REPOS=" $(tr '\n' ' ' <<<"$out")"
}
check_bot() {
  bot_repos
  [ "$BOT_REPOS" != ERROR ] || { bad "$1" bot "can't list the pr-bot's repos (run under as-bot.sh --read all)"; return; }
  [[ "$BOT_REPOS" == *" $1 "* ]] && ok "$1" bot || bad "$1" bot "the pr-bot can't reach it; add it to the installation"
}
check_hidden() { # fails closed: a repo agents must never see
  bot_repos
  [ "$BOT_REPOS" != ERROR ] || { bad "$1" hidden "can't list the pr-bot's repos (run under as-bot.sh --read all)"; return; }
  [[ "$BOT_REPOS" == *" $1 "* ]] && bad "$1" hidden "the pr-bot can reach it; remove it from the installation now" || ok "$1" hidden
}

checks=(); repos=()
while [ $# -gt 0 ]; do case "$1" in --check) checks+=("${2:?--check needs a name}"); shift 2 ;; *) repos+=("$1"); shift ;; esac; done
[ ${#checks[@]} -gt 0 ] || checks=(settings security ruleset reuse agents gitleaks bot)
for c in "${checks[@]}"; do declare -F "check_$c" >/dev/null || { echo "unknown check: $c"; exit 1; }; done
if [ ${#repos[@]} -eq 0 ]; then
  repos=(.github ouroboric yggdrasil asgard ouroboric-packages)
  for r in $LEAVES $LATER; do gh_api "repos/$ORG/$r" >/dev/null 2>&1 && repos+=("$r"); done
fi
for r in "${repos[@]}"; do for c in "${checks[@]}"; do "check_$c" "$r"; done; done
[[ " ${checks[*]} " == *" bot "* ]] && for h in $HIDDEN; do check_hidden "$h"; done
exit $fail

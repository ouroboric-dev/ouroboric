#!/usr/bin/env bash
# Check that ouroboric-dev repos have the required setup. See docs/4-ways-of-working/docs-standard.md.
#   check-repos.sh [--check settings|security|ruleset|reuse|agents|gitleaks|shared|bot|operator|services]... [repo...]
# services is not a default check and runs once per call: it keeps the services' versions equal in niflheim-local's
# pack, mimir's client-gallery-lite Dockerfile and helheim-go's template CI.
# operator fails when a tracked file in a repo's local clone names the operator who runs the check (invariant 9):
# their login, their home folder's name, or a user account in scripts/orgs/local/, matched as whole words in any
# case. CHECK_REPOS_OPERATOR (names, space-separated) replaces those names. It prints the files, never the names.
# The past records in RECORDS keep their paths as written; every other file is checked.
# The bot check also checks that the pr-bot can't reach any hidden repo. Run it under
# as-bot.sh --read all, because it reads the pr-bot's own list of repos.
# shellcheck disable=SC2015,SC2329  # `cond && ok || bad` reports only (ok and bad just print); checks run by name as check_$c
set -uo pipefail
ROOT="${CHECK_REPOS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"   # holds the side-by-side clones
ORG="ouroboric-dev"
UMBRELLAS=" ouroboric yggdrasil asgard "
FACTORIES=" yggdrasil asgard "   # the only repos with issues on
LEAVES=" gungnir odin gleipnir jormungandr midgard-react helheim-go havamal voluspa niflheim-local "
LATER=" mimir "     # standard repos checked once they exist; side-by-side clones like the umbrellas
REALMS=" midgard-react helheim-go "   # build realms; they share scripts, and helheim-go's copy is the source
SHARED=(devcontainer/checks/docs.sh devcontainer/checks/protected-common)
HIDDEN=" huldra "   # private repos that agents must never see
# Records of past work that name the founder's paths as they were; a new record names no operator.
RECORDS=(
  yggdrasil:docs/2-engineering/changes/2026-10-18-base-ci-rollout/tasks.md
  yggdrasil:docs/2-engineering/changes/2026-10-18-repo-bootstrap/tasks.md
  yggdrasil:docs/2-engineering/changes/2026-10-19-voluspa/tasks.md
  yggdrasil:docs/2-engineering/changes/2026-10-22-gallery-runtime/tasks.md
  yggdrasil:docs/2-engineering/plans/2026-10-12-yggdrasil-v0/tasks.md
  yggdrasil:docs/2-engineering/plans/2026-10-15-yggdrasil-v0-phase-1/tasks.md
  yggdrasil:docs/2-engineering/plans/2026-10-15-yggdrasil-v0-phase-2/tasks.md
  yggdrasil:docs/2-engineering/plans/2026-10-16-yggdrasil-v0-phase-3/tasks.md
  yggdrasil:docs/2-engineering/plans/2026-10-16-yggdrasil-v0-phase-4/tasks.md
  yggdrasil:docs/2-engineering/plans/2026-10-17-yggdrasil-v0-phase-5a/tasks.md
  yggdrasil:docs/2-engineering/plans/2026-10-17-yggdrasil-v0-phase-5b/tasks.md
  yggdrasil:docs/2-engineering/plans/2026-10-18-yggdrasil-v0-phase-5c/tasks.md
  yggdrasil:docs/2-engineering/plans/2026-10-22-yggdrasil-v0-phase-6/tasks.md
  yggdrasil:docs/5-research/2026-10-12-sandbox-spike.md
)
unset BOT_REPOS     # set only by bot_repos below, never from the environment
gh_api() { env -u GITHUB_TOKEN gh api "$@"; }
local_path() { if [[ "$LEAVES" == *" $1 "* ]]; then echo "$ROOT/yggdrasil/$1"; else echo "$ROOT/$1"; fi; }
fail=0
ok()  { echo "PASS $1 $2${3:+: $3}"; }
bad() { echo "FAIL $1 $2: $3"; fail=1; }

check_settings() { # GraphQL: REST hides the merge settings from tokens that can't push
  local v; v="$(gh_api graphql -f query="{repository(owner:\"$ORG\",name:\"$1\"){visibility hasIssuesEnabled hasWikiEnabled mergeCommitAllowed rebaseMergeAllowed autoMergeAllowed}}" \
    -q '.data.repository|[.visibility,.hasIssuesEnabled,.hasWikiEnabled,.mergeCommitAllowed,.rebaseMergeAllowed,.autoMergeAllowed]|map(tostring)|join(" ")')"
  local issues=false desc="no issues"   # issues are on for the factories only
  [[ "$FACTORIES" == *" $1 "* ]] && { issues=true; desc="issues on (a factory)"; }
  [ "$v" = "PUBLIC $issues false false false true" ] && ok "$1" settings || bad "$1" settings "got: $v (want public, $desc, no wiki, squash only, auto-merge on)"
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
  rules="$(gh_api "repos/$ORG/$1/rulesets/$id" -q '[.rules[]|.type+(if .type=="pull_request" then ":"+(.parameters.allowed_merge_methods|join("+"))+":"+(.parameters.required_approving_review_count|tostring)+(if .parameters.dismiss_stale_reviews_on_push then ":stale-dismissed" else "" end)+(if .parameters.require_last_push_approval then ":last-push-approved" else "" end) elif .type=="required_status_checks" then ":"+([.parameters.required_status_checks[]|.context+"@"+(.integration_id|tostring)]|sort|join("+"))+(if .parameters.strict_required_status_checks_policy then ":strict" else "" end) else "" end)]|sort|join(",")')"
  local want="deletion,non_fast_forward,pull_request:squash:1:stale-dismissed:last-push-approved"
  # A repo with lint.yml or ci.yml must require its job (lint, test) from GitHub Actions (app 15368),
  # on an up-to-date branch. Same map as setup-repo.sh.
  local pair found=()
  for pair in lint.yml:lint ci.yml:test; do
    gh_api "repos/$ORG/$1/contents/.github/workflows/${pair%%:*}" --silent >/dev/null 2>&1 && found+=("${pair##*:}@15368")
  done
  if [ ${#found[@]} -gt 0 ]; then
    want+=",required_status_checks:$(printf '%s\n' "${found[@]}" | sort | paste -sd+ -):strict"
  fi
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
check_shared() { # a realm's copy of each shared file must match helheim-go's; a missing file or clone fails
  [[ "$REALMS" == *" $1 "* ]] || { ok "$1" shared "not a realm"; return; }
  local f src dst hs hd
  for f in "${SHARED[@]}"; do
    src="$(local_path helheim-go)/$f"; dst="$(local_path "$1")/$f"
    [ -f "$src" ] || { bad "$1" shared "$src is missing"; return; }
    [ -f "$dst" ] || { bad "$1" shared "$dst is missing"; return; }
    hs="$(sha256sum < "$src")" && [ -n "$hs" ] || { bad "$1" shared "can't read $src"; return; }
    hd="$(sha256sum < "$dst")" && [ -n "$hd" ] || { bad "$1" shared "can't read $dst"; return; }
    [ "$hs" = "$hd" ] || { bad "$1" shared "$f differs from helheim-go's"; return; }
  done
  ok "$1" shared
}

svc_image() { # <pack.yaml|ci.yml> <service>: the image of that service, from `image: X` or a folded `image: >-` line
  awk -v svc="$2" '
    $0 ~ "^[ ]*" svc ":[ ]*$" { want = 1; next }
    want && $1 == "image:" { if ($2 ~ /^>/) { fold = 1; next } print $2; exit }
    fold { print $1; exit }' "$1"
}
check_services() { # once per call: the three copies of the services' versions; a missing clone fails, never skips
  local pack ci df f
  pack="$(local_path niflheim-local)/pack.yaml"
  ci="$(local_path helheim-go)/templates/api/.github/workflows/ci.yml"
  df="$ROOT/mimir/client-gallery-lite/environment/Dockerfile"
  for f in "$pack" "$ci" "$df"; do [ -f "$f" ] || { bad niflheim-local services "$f is missing"; return; }; done
  local pg s3 cipg weed pkg
  pg="$(svc_image "$pack" postgres)"; s3="$(svc_image "$pack" s3)"; cipg="$(svc_image "$ci" postgres)"
  weed="$(sed -nE 's/^FROM([[:space:]]+--[^[:space:]]+)*[[:space:]]+([^[:space:]]+)[[:space:]]+AS[[:space:]]+weed[[:space:]]*$/\2/Ip' "$df" | head -1)"
  pkg="$(grep -o 'postgresql-[0-9]\{1,\}\(=[^[:space:]\\]\{1,\}\)\{0,1\}' "$df" | head -1)"
  [ -n "$pg" ] || { bad niflheim-local services "$pack has no postgres image"; return; }
  [ -n "$s3" ] || { bad niflheim-local services "$pack has no s3 image"; return; }
  [ -n "$cipg" ] || { bad niflheim-local services "$ci has no postgres service image"; return; }
  [ -n "$weed" ] || { bad niflheim-local services "$df has no FROM ... AS weed line"; return; }
  [ -n "$pkg" ] || { bad niflheim-local services "$df installs no postgresql-<major> package"; return; }
  [ "${weed#*@}" = "${s3#*@}" ] && [[ "$weed" == *@* ]] \
    && ok niflheim-local services "weed digest ${s3#*@}" || bad niflheim-local services "$df: the weed stage is $weed, the pack's s3 is $s3"
  [ "$cipg" = "$pg" ] && ok niflheim-local services "template CI postgres image equals the pack's" \
    || bad niflheim-local services "$ci: the postgres image is $cipg, the pack's is $pg"
  local tag major pkgmajor imgminor pkgminor
  tag="${pg%%@*}"; tag="${tag##*:}"; imgminor="${tag%%-*}"; major="${imgminor%%.*}"
  pkgmajor="${pkg#postgresql-}"; pkgmajor="${pkgmajor%%=*}"
  [ "$pkgmajor" = "$major" ] || { bad niflheim-local services "$df: ${pkg%%=*} is major $pkgmajor, the pack's postgres is major $major"; return; }
  [[ "$pkg" == *=* ]] || { bad niflheim-local services "$df: ${pkg} is not pinned to a version (postgresql-$major=<version>)"; return; }
  [[ "$pkg" != *'$'* ]] || { bad niflheim-local services "$df: ${pkg} holds a variable; pin the literal version (postgresql-$major=<version>)"; return; }
  pkgminor="${pkg#*=}"; pkgminor="${pkgminor%%-*}"
  if [ "$pkgminor" = "$imgminor" ]; then ok niflheim-local services "postgres minor $imgminor (image) and $pkgminor (package)"
  else ok niflheim-local services "postgres minors differ, allowed: $imgminor (image) and $pkgminor (package)"; fi
}

operator_names() { # the names of the operator who runs the check, one per line
  local -a given
  if [ -n "${CHECK_REPOS_OPERATOR+set}" ]; then read -ra given <<<"$CHECK_REPOS_OPERATOR"; printf '%s\n' ${given[@]+"${given[@]}"}; return; fi
  printf '%s\n' "${USER:-$(id -un)}" "$(basename "$HOME")"
  local f
  for f in "${REPO_ORGS_DIR:-$(dirname "${BASH_SOURCE[0]}")/orgs}"/local/*.json; do
    [ -f "$f" ] && jq -r 'select(.owner == "user") | .org // empty' "$f" 2>/dev/null
  done
}
check_operator() {
  local d n names=() ex=() rec hits rc=0
  d="$(local_path "$1")"
  [ -e "$d/.git" ] || { bad "$1" operator "no local clone at $d"; return; }
  while IFS= read -r n; do [ -z "$n" ] || names+=(-e "$n"); done < <(operator_names | sort -u)
  [ ${#names[@]} -gt 0 ] || { bad "$1" operator "no operator names to look for"; return; }
  for rec in "${RECORDS[@]}"; do [ "${rec%%:*}" != "$1" ] || ex+=(":(exclude)${rec#*:}"); done
  hits="$(git -C "$d" grep -lIiwF "${names[@]}" -- . ${ex[@]+"${ex[@]}"})" || rc=$?   # 1: no match
  case "$rc" in
    0) bad "$1" operator "names the operator in $(paste -sd' ' - <<<"$hits")" ;;
    1) ok "$1" operator ;;
    *) bad "$1" operator "git grep failed in $d" ;;
  esac
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
[ ${#checks[@]} -gt 0 ] || checks=(settings security ruleset reuse agents gitleaks shared bot operator)
for c in "${checks[@]}"; do declare -F "check_$c" >/dev/null || { echo "unknown check: $c"; exit 1; }; done
repo_checks=(); services=0   # services compares three repos, so it runs once, not once per repo
for c in "${checks[@]}"; do if [ "$c" = services ]; then services=1; else repo_checks+=("$c"); fi; done
if [ ${#repo_checks[@]} -gt 0 ]; then
  if [ ${#repos[@]} -eq 0 ]; then
    repos=(.github ouroboric yggdrasil asgard ouroboric-packages)
    for r in $LEAVES $LATER; do gh_api "repos/$ORG/$r" >/dev/null 2>&1 && repos+=("$r"); done
  fi
  for r in "${repos[@]}"; do for c in "${repo_checks[@]}"; do "check_$c" "$r"; done; done
fi
[ "$services" = 1 ] && check_services
[[ " ${checks[*]} " == *" bot "* ]] && for h in $HIDDEN; do check_hidden "$h"; done
exit $fail

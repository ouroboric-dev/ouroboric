#!/usr/bin/env bash
# One config file per org, read by create-repo.sh, add-licences.sh, add-ci.sh, setup-repo.sh and
# new-repo.sh. Source this file; do not run it. It defines functions only.
# Founder and agents run the scripts that source it; the config lives in scripts/orgs/<org>.json
# (see scripts/orgs/README.md).
#
# Use:  . repo-config.sh; repo_config_args "$@"; repo_config_load
#   repo_config_args ARGS...      reads a leading --org <name> or --config <path>. Sets RC_FILE (absolute),
#                                 RC_REST (the other arguments) and RC_FROM (--config "$RC_FILE", to pass on).
#   repo_config_load              checks RC_FILE and sets RC_ORG, RC_LICENCE, RC_DOCS_LICENCE, RC_DOCS_PATHS,
#                                 RC_COPYRIGHT, RC_LICENCE_DIR, RC_ISSUES_ON and RC_CI.
#   repo_after_create public|private REPO   prints the config's after-create message for REPO, if any.
# Every error prints "repo-config: <message>" on stderr and exits 2.

# The RC_* variables are read by the scripts that source this file.
# shellcheck disable=SC2034
RC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rc_die() { echo "repo-config: $*" >&2; exit 2; }

# The checks, as one jq program. It prints the first problem, or nothing.
# \A and \z, not ^ and $: in jq's regexes, $ also matches before a newline.
# shellcheck disable=SC2016  # jq source, not shell
RC_CHECK='
  def isstr: type == "string";
  def name($re): isstr and test($re);
  def text: isstr and . != "" and (test("[\"\\\\\n]") | not);
  ["org","licence","docs_licence","docs_paths","copyright","licence_dir","issues_on","ci","after_create"] as $known
  | if type != "object" then "the config must be a JSON object"
    elif (keys - $known | length) > 0 then "unknown key: \(keys - $known | first)"
    elif (["org","licence","copyright"] - keys | length) > 0 then "missing required key: \(["org","licence","copyright"] - keys | first)"
    elif (has("docs_licence") != has("docs_paths")) then "docs_licence and docs_paths go together: set both or neither"
    elif (.org | name("\\A[A-Za-z0-9][A-Za-z0-9._-]*\\z") | not) then "bad org name"
    elif (.licence | name("\\A[A-Za-z0-9][A-Za-z0-9.+-]*\\z") | not) then "bad licence"
    elif (.copyright | text | not) then "copyright must be non-empty with no \", \\ or newline"
    elif has("docs_licence") and (.docs_licence | name("\\A[A-Za-z0-9][A-Za-z0-9.+-]*\\z") | not) then "bad docs_licence"
    elif has("docs_paths") and ((.docs_paths | type) != "array" or (.docs_paths | length) == 0) then "docs_paths must be a non-empty array"
    elif has("docs_paths") and (.docs_paths | all(text) | not) then "each docs path must be non-empty with no \", \\ or newline"
    elif has("licence_dir") and (.licence_dir | isstr and . != "" | not) then "licence_dir must be a non-empty string"
    elif has("issues_on") and ((.issues_on | type) != "array" or (.issues_on | all(name("\\A[A-Za-z0-9][A-Za-z0-9._-]*\\z")) | not)) then "issues_on must be an array of repo names"
    elif has("ci") and ((.ci | type) != "array" or (.ci | all(name("\\A[a-z0-9-]+\\z")) | not)) then "ci must be an array of names like reuse"
    elif has("after_create") and ((.after_create | type) != "object" or ((.after_create | keys) - ["public","private"] | length) > 0 or (.after_create | to_entries | all(.value | isstr) | not)) then "after_create must hold only public and private strings"
    else empty end'

repo_config_args() {
  RC_FILE='' RC_REST=() RC_FROM=() RC_WANT_ORG=''
  case "${1:-}" in
    --org)
      [ $# -ge 2 ] || rc_die "--org needs a name"
      [[ "$2" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || rc_die "bad org name: $2"
      RC_WANT_ORG="$2"
      RC_FILE="${REPO_ORGS_DIR:-$RC_DIR/orgs}/$2.json"
      shift 2
      ;;
    --config)
      [ $# -ge 2 ] || rc_die "--config needs a path"
      RC_FILE="$2"
      shift 2
      ;;
    *) rc_die "name an org: --org <name> or --config <path>" ;;
  esac
  [ -f "$RC_FILE" ] || rc_die "$RC_FILE: no such file"
  RC_FILE="$(cd "$(dirname "$RC_FILE")" && pwd)/$(basename "$RC_FILE")"
  RC_REST=("$@")
  RC_FROM=(--config "$RC_FILE")
}

repo_config_load() {
  local problem dir
  jq -e . "$RC_FILE" >/dev/null 2>&1 || rc_die "$RC_FILE: not valid JSON"
  problem="$(jq -r "$RC_CHECK" "$RC_FILE")" || rc_die "$RC_FILE: cannot be checked"
  [ -z "$problem" ] || rc_die "$RC_FILE: $problem"
  RC_ORG="$(jq -r .org "$RC_FILE")"
  if [ -n "${RC_WANT_ORG:-}" ] && [ "$RC_ORG" != "$RC_WANT_ORG" ]; then
    rc_die "$RC_FILE: org is $RC_ORG, but --org says $RC_WANT_ORG"
  fi
  RC_LICENCE="$(jq -r .licence "$RC_FILE")"
  RC_DOCS_LICENCE="$(jq -r '.docs_licence // ""' "$RC_FILE")"
  RC_COPYRIGHT="$(jq -r .copyright "$RC_FILE")"
  RC_DOCS_PATHS="$(jq -r '[(.docs_paths // [])[] | tojson] | join(", ")' "$RC_FILE")"
  RC_ISSUES_ON="$(jq -r '(.issues_on // []) | if length == 0 then "" else " " + join(" ") + " " end' "$RC_FILE")"
  RC_CI="$(jq -r '(.ci // ["reuse","markdown","actions"]) | join(",")' "$RC_FILE")"
  RC_LICENCE_DIR=''
  dir="$(jq -r '.licence_dir // ""' "$RC_FILE")"
  if [ -n "$dir" ]; then
    case "$dir" in /*) ;; *) dir="$(dirname "$RC_FILE")/$dir" ;; esac
    RC_LICENCE_DIR="$(cd "$dir" 2>/dev/null && pwd)" || rc_die "$RC_FILE: licence_dir does not exist: $dir"
  fi
}

repo_after_create() {
  local msg
  msg="$(jq -r --arg v "$1" --arg r "$2" '.after_create[$v] // "" | gsub("\\{repo\\}"; $r)' "$RC_FILE")"
  [ -z "$msg" ] || printf '%s\n' "$msg"
}

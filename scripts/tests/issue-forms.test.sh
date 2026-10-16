#!/usr/bin/env bash
# Tests for the factories' issue forms, in the side-by-side clones.   scripts/tests/issue-forms.test.sh
# A repo whose clone or .github/ISSUE_TEMPLATE folder is absent is skipped, so CI without clones stays green.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ISSUE_FORMS_ROOT:-$(cd "$HERE/../../.." && pwd)}"   # holds the side-by-side clones
fail=0
check() { local d="$1"; shift; if "$@" 2>/dev/null; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi; }

# form_ok <file>: valid YAML with the top-level keys GitHub's issue-form schema requires
form_ok() {
  python3 -I - "$1" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
try:
    import yaml
except ImportError:
    # Minimal check without PyYAML: the required keys at column 0, no tabs.
    import re
    sys.exit(0 if "\t" not in text and all(re.search(r"^%s:" % k, text, re.M) for k in ("name", "description", "body")) else 1)
d = yaml.safe_load(text)
ok = isinstance(d, dict) and all(k in d for k in ("name", "description", "body")) \
    and isinstance(d["body"], list) and len(d["body"]) > 0
sys.exit(0 if ok else 1)
PY
}
mentions() { grep -qi -- "$2" "$1"; }

for repo in yggdrasil asgard; do
  dir="$ROOT/$repo/.github/ISSUE_TEMPLATE"
  if [ ! -d "$dir" ]; then echo "SKIP $repo: no $dir (clone or issue forms absent)"; continue; fi
  for f in bug improvement; do
    p="$dir/$f.yml"
    check "$repo $f.yml exists" [ -f "$p" ]
    check "$repo $f.yml is a valid issue form (name, description, body)" form_ok "$p"
    check "$repo $f.yml asks for the factory version" mentions "$p" 'version'
    check "$repo $f.yml asks for the config hash" mentions "$p" 'config hash'
    check "$repo $f.yml warns against private code, data or secrets" bash -c "grep -qi 'private' '$p' && grep -qi 'code' '$p' && grep -qi 'data' '$p' && grep -qi 'secret' '$p'"
  done
  check "$repo config.yml exists" [ -f "$dir/config.yml" ]
  check "$repo config.yml turns off blank issues" grep -Eq '^blank_issues_enabled: *false[[:space:]]*$' "$dir/config.yml"
done
exit $fail

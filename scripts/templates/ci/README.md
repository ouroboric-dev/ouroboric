# The base CI

`add-ci.sh` writes the base CI into a repo: `.pre-commit-config.yaml`, `.github/workflows/lint.yml` (the
required check `lint`) and the files that some pieces ship. The config is built from pieces, one per tool.
Every hook revision is pinned to a release tag.

## The pieces

| Piece | Hook | Ships |
| --- | --- | --- |
| `gitleaks` | gitleaks, plus `gitleaks-history` (manual stage, the whole history) | |
| `reuse` | reuse-tool, `reuse lint` | |
| `markdown` | markdownlint-cli2. The config bends four rules: MD025 lets front matter `title:` and an H1 coexist; MD010 ignores code blocks, because gofmt requires tabs and the plan tools copy plan code verbatim; MD033 allows `<picture>`, `<source>` and `<img>`, because the docs standard prescribes `<picture>` for themed images and the org profile opens with `<img>`; MD041 is off, because journal entries, PR templates, Claude skill files and the org profile banner open without an H1 on purpose, and the docs standard's front matter rule already checks every other doc's title | `.markdownlint.yaml` |
| `shell` | shellcheck-py | |
| `actions` | actionlint | |
| `yaml` | yamllint | `.yamllint.yaml` |

`gitleaks` is always first, even when nobody lists it.

## Choosing pieces

The org config's `ci` list names the pieces. `--ci <piece>,...` replaces that list for one run. A repeated
name is kept once, in first-seen order. An empty item (`reuse,,markdown`) or an unknown piece exits 2 and
writes nothing.

## The piece format

A piece is one file in `pieces/`. `add-ci.sh` enforces these rules and names the piece and the rule that fails:

- The file is `<name>.yaml`, and the name matches `^[a-z0-9-]+$`.
- It has exactly one line matching `^  - repo: https://`.
- It has exactly one line matching `^    rev: `, whose value matches
  `^v?[0-9]+(\.[0-9]+)+([.-][0-9A-Za-z]+)*$` (a release tag, never a branch).
- It has a line matching `^    hooks:`.
- It has no tabs.

Each line is indented as it will be under `repos:`, because `add-ci.sh` appends the files in order.

A piece may have a `<name>.files/` folder. Its files are copied into the repo at the same relative paths.
Two pieces must not ship the same path.

Realms will ship their own pieces in this format later (the repo-bootstrap proposal, future work item 3).

## Existing repos

`add-ci.sh --upgrade` also works on a repo whose `.pre-commit-config.yaml` is the old gitleaks-only scaffold
(`upgrade/gitleaks-only.yaml`). It replaces that file, and adds `lint.yml` and the piece files. If the config
differs by even one byte, it exits 2 and writes nothing; every other target must still not exist.

## Bumping a pin

Change the `rev` in a reviewed pull request. The release must be at least two weeks old. For `lint.yml`, the
action SHAs and `pre-commit==...` follow the same rule. Run `bash scripts/tests/add-ci.test.sh` before the
pull request, because it runs every hook for real.

An org whose Actions policy allows only listed actions (ouroboric-dev's does) must list both of `lint.yml`'s
actions, `actions/checkout` and `actions/setup-python`, at the exact SHAs it pins. Otherwise `lint` ends in
`startup_failure` and never runs. So a bump of either action SHA also updates the org's allowlist.

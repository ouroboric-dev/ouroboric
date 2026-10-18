# Org configs

One JSON file per org, `scripts/orgs/<org>.json`. The repo scripts read it with `--org <org>`, or with
`--config <path>` for a file elsewhere. To add an org, copy `ouroboric-dev.json` as the example and
change the values. A key that is not listed here, or a value that breaks a rule, stops the script with
exit code 2.

| Key | Required | Meaning |
| --- | --- | --- |
| `org` | yes | The GitHub org. It must equal the name given to `--org`. Letters, digits, `.`, `_`, `-`; starts with a letter or digit. |
| `licence` | yes | SPDX id of the main licence, such as `AGPL-3.0-only`. Letters, digits, `.`, `+`, `-`. |
| `docs_licence` | with `docs_paths` | SPDX id of the licence for the docs. Set both `docs_licence` and `docs_paths`, or neither. |
| `docs_paths` | with `docs_licence` | Non-empty list of path globs that take `docs_licence`, such as `["docs/**", "README.md"]`. |
| `copyright` | yes | The copyright holder. Non-empty, with no `"`, `\` or newline. Non-ASCII letters are fine. |
| `licence_dir` | no | Folder with the licence texts. A relative path counts from the config file's folder. |
| `issues_on` | no | Repos that keep GitHub issues on. All other repos have issues off. |
| `ci` | no | Pieces of the base CI: `reuse`, `markdown`, `actions`. If absent, all three. |
| `after_create` | no | Messages for the founder after a repo is created: `public` and `private`. `{repo}` becomes the repo name. |

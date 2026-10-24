# Org configs

One JSON file per org, `scripts/orgs/<org>.json`. An operator's own account, with `"owner": "user"`,
has its config in [`local/`](local/README.md), which git ignores: never commit one. The repo scripts
read a config with `--org <name>`, from either folder, or with `--config <path>` for a file elsewhere.
To add an org, copy `ouroboric-dev.json` as the example and change the values. A key that is not listed here, or a value that breaks a rule, stops the script with
exit code 2.

| Key | Required | Meaning |
| --- | --- | --- |
| `org` | yes | The GitHub org, or the user for `"owner": "user"`. It must equal the name given to `--org`. Letters, digits, `.`, `_`, `-`; starts with a letter or digit. |
| `owner` | no | `org` (the default) or `user`. [A user's account](#a-users-own-account) gets the same setup, with the differences below. |
| `licence` | yes | SPDX id of the main licence, such as `AGPL-3.0-only`. Letters, digits, `.`, `+`, `-`. |
| `docs_licence` | with `docs_paths` | SPDX id of the licence for the docs. Set both `docs_licence` and `docs_paths`, or neither. |
| `docs_paths` | with `docs_licence` | Non-empty list of path globs that take `docs_licence`, such as `["docs/**", "README.md"]`. |
| `copyright` | yes | The copyright holder. Non-empty, with no `"`, `\` or newline. Non-ASCII letters are fine. |
| `licence_dir` | no | Folder with the licence texts. A relative path counts from the config file's folder. Without it, the texts come from `reuse download` through uvx, which needs the network. ouroboric-dev's `../../LICENSES` resolves only inside the ouroboric repo. |
| `issues_on` | no | Repos that keep GitHub issues on. All other repos have issues off. |
| `ci` | no | Pieces of the base CI, such as `reuse` ([the pieces](../templates/ci/README.md)). If absent or empty, only gitleaks runs. |
| `after_create` | no | Messages for the founder after a repo is created: `public` and `private`. `{repo}` becomes the repo name. |

With a `docs_licence`, `docs_paths` should cover `README.md`. The first commit of `new-repo.sh` holds that
README as its only docs file, and `reuse lint` fails on a licence text that no file uses.

Another org should give its bots access to a new repo only after `new-repo.sh` succeeds, and its
`after_create` message should say so.

## A user's own account

Any operator can make repos on their own account, outside the company, with the same setup. The
config lives in [`local/`](local/README.md), copied from [`examples/user.json`](examples/user.json).
The example licence is `LicenseRef-Proprietary`, with a text that names no one: the holder is the
config's `copyright`, in `REUSE.toml`. The scripts work as for an org, with these differences:

- The token is fine-grained, short-lived and owned by the user, with the same access as the org's
  token. `create-repo.sh` checks that the token belongs to the config's user before it creates anything.
- `setup-repo.sh` writes each repo's own Actions allowlist: the actions that `lint.yml` pins, at their
  SHAs, and nothing else. A user has no org to hold the list.
- A private repo gets no secret scanning, push protection or private vulnerability reporting, because
  GitHub offers none of them there. Gitleaks in `lint` is the guard.
- GitHub applies rulesets to a user's private repo only with GitHub Pro. Without it, `setup-repo.sh`
  fails and says that `main` is not protected. Upgrade, or make the repo public, then run
  `setup-repo.sh` again.
- The user is the only person with write access, so nobody else can approve a pull request. The user
  merges through the admin bypass, which the ruleset still allows only for a pull request.
- The pr-bot is installed on ouroboric-dev only, so agents can't reach the repo. To let them in, install
  a bot on the account for that repo alone.
- Agents never write an operator's config. The operator copies the example and fills it in.

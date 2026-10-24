# Operator configs

This folder holds each operator's own configs, such as the config for repos on your own GitHub
account. Git ignores everything here except this README, so a config never leaves your machine.
Never commit one ([invariant 9](../../../AGENTS.md#invariants)).

`--org <name>` reads `scripts/orgs/<name>.json` or `scripts/orgs/local/<name>.json`. A name in both
places stops the script.

To set up your own account:

1. Copy [`../examples/user.json`](../examples/user.json) to `<your-github-user>.json` here.
2. Set `org` to your GitHub user, `copyright` to your name, and `licence_dir` to `<your-github-user>`.
3. Copy [`../examples/LicenseRef-Proprietary.txt`](../examples/LicenseRef-Proprietary.txt) into a
   folder `<your-github-user>/` here, or put your own licence text there and change `licence`.
4. Run `new-repo.sh --org <your-github-user> [--private] <repo> "<description>"` with your own token
   ([the differences from an org](../README.md#a-users-own-account)).

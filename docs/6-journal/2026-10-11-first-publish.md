---
date: 2026-10-11
tags: [publishing, security, github, tooling]
status: resolved
post-candidate: yes
evidence: [../1-company/readiness/2026-10-11-ready-to-build.md, "https://github.com/ouroboric-dev"]
---
## Challenge

Publish the first version: four public repositories, set up properly, with nothing private in them.

## Context

Publishing can't be undone: anything public can be copied and archived within minutes, including the
full git history.

## Options

Push as is, or scan, scrub and harden first.

## Decision

Scan and harden first: a secret scan and a private-data scan over the full history of every repo;
history squashed where an earlier draft held private details; author email changed to a professional
address; licences chosen; then repositories created with issues off, Discussions on, secret scanning
with push protection, Dependabot alerts, private vulnerability reporting, and a `main` branch that
can't be force-pushed or deleted.

## Result

Four public repositories, all checks verified on GitHub after the push. Not everything went as planned:

- GitHub's Free plan doesn't allow restricting public repository creation to admins.
- Organisation-wide Actions settings and rules need the `admin:org` scope, which the token lacked; the
  branch protection went in per repository instead.
- The Podman VM couldn't mount WSL paths, so the secret scan streamed each repository into the
  container instead. That breaks the sandbox design's bind mounts, and is now a spike item.
- A work credential helper fired on a public image pull again, so image pulls now use an isolated,
  empty auth configuration, and the sandbox driver must do the same.

## Lessons

- Git history publishes everything that ever was. Clean the history before the first push, not after.
- Commit metadata leaks too: the author email is on every commit.
- Tooling tasks are environment probes. Three of the four surprises here were facts about the machine,
  not about the design, and each one changed the design.

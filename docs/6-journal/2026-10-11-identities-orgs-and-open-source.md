---
date: 2026-10-11
tags: [security, github, open-source]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#151-github-remote-and-identities]
---
## Challenge

Full autonomy means bots pushing and merging, with branch protection, possibly on open-source
products. The factory lives in one org and its products may live in others, public or private.

## Context

marola's MIP-0086 splits automation into a PR bot (proposes) and a merge bot (lands).

## Options

Agents with their own tokens; factory-held bot identities; GitHub work in v0 or iteration 2.

## Decision

- Agents hold no GitHub credentials; the factory pushes and opens PRs for them.
- Two operator-owned GitHub Apps (created from a shipped manifest), per-org installations, tokens
  minted per operation for one repo and one hour.
- Rulesets: one human approval, bypass only for admins and the merge bot. Merges from the host,
  never from CI.
- The factory repo is the product; each operator has a private instance listing their projects.
  Project visibility and hosting are the operator's choice.
- Built in iteration 2; v0 is local git only.

## Result

Pending.

## Lessons

Two concrete open-source traps:

- A merge key in a public repo's CI can be read through a careless `pull_request_target` workflow;
  App keys never expire, so it opens every installed repo.
- Unattended mode plus public issues is a prompt-injection pipeline ("please add this analytics
  snippet"). Only human-approved work becomes factory work.

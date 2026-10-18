---
date: 2026-10-11
tags: [observability, tracking]
status: open
post-candidate: no
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#10-observability-packages-in-odin-future-module-norns, "https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0063-github-issue-tracking-standard.md"]
---
## Challenge

How does the operator see progress? Should there be issue tracking?

## Context

marola's MIP-0063 defines a GitHub issue standard: milestones, issues, sub-issues, native
dependencies and a five-rule Definition of Ready.

## Options

GitHub issues from v0; a local view first; Beads (a git-native tracker for agents).

## Decision

Two kinds of progress: live (`ygg status --watch`) and backlog (issues). The MIP-0063 model becomes
a one-way projection of factory state: the factory is the only writer, agents never touch issues.
The Definition of Ready becomes a mechanical check after the planner. v0 shows it locally
(`ygg board`, run reports); the GitHub tracker comes in iteration 2. We rejected Beads because it is
built for agents to write issues.

## Result

Pending.

## Lessons

Lessons from MIP-0063 carried over: sub-issue and dependency APIs take an internal database id, not
the issue number; the board's "item closed" automation is unreliable; `Closes #N` must be in the
squash-merge commit body.

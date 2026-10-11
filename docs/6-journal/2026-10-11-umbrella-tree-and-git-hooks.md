---
date: 2026-10-11
tags: [graph, topology, security, validation]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#3-repository-topology-and-isolation]
---
## Challenge
How to isolate agents from the orchestrator's files while keeping a high-level view, inspired by
marola's umbrella repo with submodules.

## Context
The operator runs Claude from an umbrella repo whose submodules are the real repos. Proposal: one
umbrella for the factory, one per project, then the project's repos, possibly deeper.

## Options
A single workspace folder per run, or a recursive tree of umbrellas and leaves.

## Decision
A recursive umbrella/leaf tree. Agents only ever mount one leaf; the factory is the only writer of
umbrellas. A submodule's pointer becomes the validation record: it moves only after that level's
tests pass, one level per move, with contract changes as approval points.

Designing this exposed a hole in the earlier sandbox design: the agent could write `.git/hooks/`
inside its workspace, and the factory commits from the host, so git would run the agent's hook
outside the sandbox. Submodules fix it neatly: a submodule's git data lives in the parent's
`.git/modules/`, out of the agent's mount. Host git also runs with hooks disabled.

## Result
Pending.

## Lessons
- Reusing a structure you already know (marola) made the design easier to think about and surfaced
  a security hole the new design had missed.
- Deeper trees make cascades steeper: a bad leaf commit auto-promoted through every level would be
  "certified" everywhere at once. Hence one level per move.

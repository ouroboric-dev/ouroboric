---
date: 2026-10-10
tags: [graph, spec-driven, measurement]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#42-the-web-realm-graph]
---
## Challenge
The operator already ran a Spec Kit + Superpowers setup (Spec Kit plans, Superpowers executes with
subagents). Should the factory use them?

## Context
Both are in-session workflows: slash commands and auto-triggered skills inside one agent session.
The factory is an outer orchestrator.

## Options
- Nest them as they are inside factory nodes.
- Use Spec Kit live from day one.
- Borrow their artifacts and practices now, plug the real tools in later.

## Decision
Borrow, then plug in. v0 uses Spec Kit's artifact layout (`spec.md`, `plan.md`, `tasks.md`) and turns
Superpowers' practices into graph structure: a fresh session per task, two read-only reviewers
(spec compliance, then code quality), and a mechanical TDD check (new tests must fail on the parent
commit). Later, real Spec Kit becomes a swappable planning strategy, benchmarked against native
planning.

## Result
Pending: the planned Spec Kit vs native planning benchmark.

## Lessons
Nesting an orchestrator inside an orchestrator hides exactly what you want to measure. Superpowers'
subagent execution is itself an orchestrator, so inside a factory node its tasks, retries and costs
would be invisible to the factory's metrics.

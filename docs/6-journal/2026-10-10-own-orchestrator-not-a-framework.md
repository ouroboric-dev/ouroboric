---
date: 2026-10-10
tags: [graph, architecture, frameworks]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#18-decision-log, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/5-research/research-stack.md]
---
## Challenge

Build the orchestrator ourselves, or build on an existing framework?

## Context

The main goal is learning, and models and tools must be swappable.

## Options

- **Own small orchestrator:** a graph engine over agent CLIs, state in files and git.
- **LangGraph.js:** checkpoints and human interrupts for free, but built around model API calls, and
  resuming re-runs a whole node (expensive when a node is a multi-dollar agent session).
- **Claude Code native features** (skills, hooks, subagents, workflows): fastest start, but lock-in.
- Later raised: **CrewAI** and similar (AutoGen, ADK, Mastra).

## Decision

Own orchestrator. Frameworks like CrewAI orchestrate API-level agents (a model plus tools), which are
much weaker coders than coding-agent CLIs with their tuned harnesses, and they hide the parts we want
to learn. We study Gas Town, MetaGPT and ChatDev as prior art; OpenHands is a future adapter;
container-use is a candidate sandbox driver.

## Result

Pending: whether the orchestrator stays small (the estimate was a few hundred lines for
checkpoint/resume and retries at v0 size).

## Lessons

"Framework or not" depends on what the agents are. When the agents are whole CLIs, most agent
frameworks orchestrate the wrong thing.

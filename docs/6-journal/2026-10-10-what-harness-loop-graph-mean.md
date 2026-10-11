---
date: 2026-10-10
tags: [research, harness, loop, graph]
status: resolved
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/5-research/research-harness.md, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/5-research/research-loops-graphs.md]
---
## Challenge
Understand what harness, loop and graph engineering mean in practice before designing anything.

## Context
Starting reference: walkinglabs/learn-harness-engineering. Research widened to Anthropic's and
OpenAI's engineering posts, Thoughtworks, StrongDM, Stripe and others (see the research briefs).

## Options
Read widely and synthesise, or start from one framework's vocabulary. We read widely.

## Decision
Working definitions:
- **Harness:** everything around the model (instructions, state files, tools, checks, permissions,
  session start and end). "Agent = model + harness."
- **Loop:** build → check → fix, which only works with a fast, trustworthy checker that is not the
  agent grading itself, plus iteration and budget caps.
- **Graph:** fixed structure around loops: plain code for steps that need no judgment, agents for
  judgment, capped retries, human approval points.

## Result
The research found two facts that shaped the whole design:
- Harness-only changes move results a lot. In Anthropic's game-maker experiment, the same model
  produced a game that didn't respond to input in a solo run ($9, 20 minutes) and a playable game
  with a planner/generator/evaluator harness ($200, 6 hours).
- Verification is the bottleneck. Every serious source invests in sandboxes, checks and repo docs
  rather than prompts.

## Lessons
The interesting work is not prompting. It is building the checker, the boundaries and the memory
the agent works inside.

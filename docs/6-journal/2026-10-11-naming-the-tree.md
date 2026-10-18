---
date: 2026-10-11
tags: [naming, branding, modularity]
status: resolved
post-candidate: yes
evidence: [../7-branding/story/naming-and-mythology.md]
---
## Challenge

Name the factory and its components, with modularity in mind: specialised factories assembled from
components that respect a shared contract.

## Context

Starting names: Vitruvius (harness), Ouroboros (loop), Yggdrasil (graph, and maybe the factory).
Ouroboros and Yggdrasil matched; Vitruvius worked alone but didn't match the theme.

## Options

A Norse set, a Greek set (Daedalus, Labyrinth, Ariadne, Mnemosyne), or keeping Vitruvius.

## Decision

The Norse set:

- Yggdrasil = the factory (and its source umbrella);
- Odin = the orchestrator, with a built-in warning (Fenrir swallows Odin at Ragnarok);
- Gleipnir = the harness (the silk-thin binding that held the wolf Fenrir);
- Jormungandr = the loop;
- Gungnir = the component contract (the spear oaths were sworn on);
- Ouroboros = the brand symbol only, matching the org `ouroboric-dev`.

Also named: Ratatoskr (routing), Norns (observability), Mimir (benchmarks), realms (packs), and the
adversaries Loki (prompt injection), Nidhogg (entropy) and Ragnarok (the cascade).

## Result

Recorded in `naming-and-mythology.md`.

## Lessons

- A theme is a design tool: a myth that explains a component's job in one sentence makes names
  memorable and future naming easy.
- Practical filters matter as much as meaning: we rejected "Askr" (the ash of Yggdrasil) because it
  reads like "ask"; Jormungandr is spelled in ASCII; we checked collisions (Yggdrasil is also a
  well-known Go network project).
- The operator didn't always take the recommendation (Jormungandr over the suggested Draupnir), and
  that's fine: the record shows both.

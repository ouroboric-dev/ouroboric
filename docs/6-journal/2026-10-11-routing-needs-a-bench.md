---
date: 2026-10-11
tags: [routing, measurement]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#8-routing-package-in-odin-future-module-ratatoskr, "https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0084-zero-setup-routing.md", "https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0085-routing-index-family.md"]
---
## Challenge

As the tree grows, agents and the orchestrator need help finding where work belongs. marola already
used graphify for routing, but had no validation layer.

## Context

marola's MIP-0084 found graph routing had essentially zero use outside the sessions that built it,
because reaching it needed setup. MIP-0085 splits routing into one index per type of question, and
ships each index only if it beats a question bench.

## Options

One big graph, or an index family per umbrella, measured by a bench.

## Decision

Per-umbrella routing bundles built by deterministic programs, with a short summary injected into
each agent's context (no setup). v0 indexes: wiring/contracts, impact, doc↔code, decisions. The
impact index connects routing to validation: it decides which acceptance tests run and whether a
pointer move counts as a contract change. Every generated file gets a shrink guard.

## Result

Pending: routing usage and bench right-first scores in the ledger.

## Lessons

A routing tool nobody reaches has zero value, however good it is. Measure use, not just quality.

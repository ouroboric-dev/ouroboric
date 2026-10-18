---
date: 2026-10-11
tags: [process, kickstart, charter, docs]
status: resolved
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/charter.md, ../4-ways-of-working/spec-driven-development.md, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/design/2026-10-11-yggdrasil-v0-design.md, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md]
---
## Challenge

The founding document didn't fit the spec-driven process it helped define. It mixed three altitudes:
project-level direction (learning first, no lock-in, open source), v0's design (what v0 delivers and
how success is judged), and v0's engineering spec (most of its 850 lines). The process started at the
design-doc level and had no home for the first one.

## Context

Treating the founding document as a permanent special case would undermine the ouroboric principle:
the factory should document itself exactly as it documents what it builds.

## Options

- Keep one combined document as an acknowledged exception.
- Add a kickstart stage for new products, and retrofit Yggdrasil through it.

## Decision

A **tier 0 kickstart** for every new product: intent and research → **charter** (vision, mission,
principles, users and problems, north-star measures, boundaries; human-approved) → shape (realms,
repo tree, org, visibility, hosting) → brand seed → roadmap → milestone 1's design doc, after which
the regular flow applies. A charter-conformance check stops design docs that drift from the charter,
and the charter's principles become `AGENTS.md` invariants. Benchmark briefs skip tier 0.

Then we ran Yggdrasil through it after the fact: a charter written from the founding sessions, and
the combined document split into a short v0 design doc and a v0 engineering spec, with every
cross-reference and link remapped. We removed the process's stage-0 exception.

## Result

Yggdrasil's own documents now follow the same structure as any product's, with no exceptions.

## Lessons

- When a document doesn't fit the process, look for a missing stage before granting an exception.
- Mixing altitudes in one document hides which parts need a human: direction (charter, design doc)
  versus execution (spec, plan).
- Mechanical refactors of docs need the same care as code: an automated renumbering silently changed
  a reference the script had just inserted, and a link and anchor check caught it.

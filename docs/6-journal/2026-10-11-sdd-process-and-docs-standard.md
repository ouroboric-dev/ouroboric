---
date: 2026-10-11
tags: [process, spec-driven, docs, self-hosting, simplicity]
status: open
post-candidate: yes
evidence: [../4-ways-of-working/spec-driven-development.md, ../4-ways-of-working/docs-standard.md, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/design/2026-10-11-yggdrasil-v0-design.md]
---
## Challenge
The design named artifacts (spec, plan, tasks) but no process around them, and no documentation
standard, for the factory or for the products it builds. Plus a question: can Yggdrasil build itself?

## Context
Spec Kit, OpenSpec, Superpowers, BMAD and others each bring their own process. Critiques of
spec-driven tools say they are heavy and that agents ignore big specs. The operator had good
experience with a separate design-doc layer (PRD-like, product-owned) above an RFC-like spec.

## Options
- Adopt one tool's process, or define a tool-agnostic process with artifacts as a contract.
- One approval level for all documents, or approval matched to what each document decides.
- Renderers: Material for MkDocs (as in marola), Zensical, Starlight, Docusaurus.

## Decision
- **Process:** design doc (human approves, in every mode by default) → spec (automatic when a
  conformance reviewer finds it within the design doc; stops on deviation) → plan, tasks and build
  (automatic except in step-by-step mode). The rule: humans approve direction; deviations stop;
  building within direction is automatic. Tiers 1–3 scale ceremony to change size; OpenSpec-style
  change proposals with spec deltas keep a living spec current.
- **Tools are strategies:** Spec Kit, OpenSpec and others plug in as planning strategies; Ponytail
  plugs in as a reuse and simplicity reviewer, invoked explicitly and vendored (an independent test
  found it activated on its own in zero of ten sessions).
- **Self-hosting:** yes, staged like a compiler bootstrapping itself; stage 1 is the milestone after
  v0. Never build in place; `guardrail-change` is a hard approval point.
- **Docs:** one numbered template for the factory and every product, with a branding section that
  feeds identity, voice and copy; Zensical as renderer, docs kept renderer-agnostic.

## Result
Pending: whether the design-conformance reviewer catches real deviations, and the Ponytail on/off
benchmark.

## Lessons
- Approval belongs where direction is decided. Approving every document wastes attention; approving
  none lets the factory decide what to build.
- A self-improving factory needs protection from itself: one "reasonable fix" that deletes a
  security test, shipped and then used to review the next version, erodes the harness version by
  version.
- Material for MkDocs went into maintenance mode in November 2025; check a tool's status before
  copying a setup from an older project.

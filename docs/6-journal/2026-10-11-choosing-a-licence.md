---
date: 2026-10-11
tags: [licensing, open-source, publishing]
status: resolved
post-candidate: yes
evidence: [../1-company/legal/README.md, ../../TRADEMARKS.md]
---
## Challenge

Choose licences before publishing. The goals: open source from day one, build in public and get
recognition; operators keep what they build; the option to build closed components later; and no one
cloning the work, improving it, and selling it as a closed product.

## Context

Most agent tools use MIT or Apache-2.0 (OpenHands, OpenCode, Codex CLI, Goose, Aider, Spec Kit), which
allow closed, paid copies. A few use AGPL-3.0 (Claude Squad; outside agent tools, Grafana switched to
it in 2021 to stop closed clones). Some use source-available licences (Crush uses FSL).

## Options

- A source-available no-compete licence (FSL, PolyForm Shield): blocks competitors, but isn't open
  source, which contradicted the charter.
- Apache-2.0 everywhere: maximum adoption, but closed paid copies are allowed.
- AGPL-3.0 for the core, with permissive licences where code is copied into operators' products.

## Decision

AGPL-3.0 for factory code, MIT for anything copied into what operators build (templates, scaffolds,
skills), CC BY 4.0 for docs, names and logos reserved by a trademark policy. What operators build is
theirs; a "Built with Ouroboric" notice is on by default and requested, not required. A contributor
licence agreement comes before the first outside contribution.

## Result

Licensing files, a machine-readable REUSE map and a trademark policy in every repository; readiness
items RB-08 and RB-09 met.

## Lessons

- "No competing products" and "open source" are mutually exclusive: the Open Source Definition forbids
  restricting fields of use. AGPL gets close to the goal while staying open: it blocks *closed* copies,
  not paid ones.
- Copyleft must not leak into users' work. Templates copied into products need a permissive licence,
  or every product built with the factory would inherit the AGPL.
- Required attribution in private products' interfaces can't be enforced and drives users away;
  default-on attribution plus trademark protection gives recognition without that cost.

---
date: 2026-10-11
tags: [architecture, company, asgard, readiness]
status: open
post-candidate: yes
evidence: [../1-company/charter.md, ../1-company/readiness/2026-10-11-ready-to-build.md, "https://github.com/ouroboric-dev/asgard/blob/main/templates/readiness/checklist.md"]
---
## Challenge

The software factory had quietly become a company and product factory: charters, branding, legal and
readiness sat inside the software factory's repo, although they aren't software-factory
concerns. They feed it, the way a company's principles and culture feed its engineering.

## Context

The design already had a recursive repo tree, a tier 0 kickstart and a charter. The founder's view of
Ouroboric is broader than one factory: products that follow the ouroboric philosophy, starting with
software and company factories, possibly later product, research and artistic factories.

## Options

- Keep everything in the software factory's repo.
- Split into a company umbrella with two products: a software factory and a company factory, with the
  company factory running on the software factory's engine.

## Decision

- **Ouroboric** is the company umbrella: company charter (abstract vision and mission, the meaning of
  "ouroboric", principles, values, portfolio), roadmap, legal, readiness, journal, branding, and the
  shared standards.
- **Yggdrasil** (software factory) keeps its product charter, design doc, spec and research.
- **Asgard** (company factory) produces direction: kickstart, brand seed, legal basics, roadmaps and
  readiness. It runs on Odin as direction realms; its kickstart graph is Ginnungagap.
- **Readiness** is a checklist with three levels (ready to build, launch, promote); every item has
  evidence or is marked missing. We ran the first assessment on Ouroboric itself.

## Result

The first assessment: 4 items met, 10 partial, 6 missing. The gaps are reviews, a licence, ownership
clarity, credentials and caps, and the plan.

## Lessons

- Watch for scope that grows into a different kind of thing. The tell was documents with no
  software-factory reader: charters, brand stories, legal.
- A recursive tree pays off: adding a company level above products needed no new mechanism.
- Readiness checklists find what design reviews don't: no licence (published code without one is
  "all rights reserved"), unclear ownership, missing credentials. None of these were design questions.

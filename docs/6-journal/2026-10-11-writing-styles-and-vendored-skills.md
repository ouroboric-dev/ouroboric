---
date: 2026-10-11
tags: [docs, writing, skills, supply-chain]
status: open
post-candidate: yes
evidence: [../4-ways-of-working/writing-styles.md, ../4-ways-of-working/docs-standard.md]
---
## Challenge
Legal text, engineering specs, runbooks, the brand story and agent instructions need very different
writing. Which styles, applied at which level, enforced how?

## Context
Writing-style skills were available (ASD-STE100, plain language, GOV.UK, Google developer docs,
Orwell's rules, AP, Scott Adams), plus humanizer for removing AI tells. The docs already followed a
numbered template.

## Options
One style everywhere; a style per section; per-document overrides; skills only, or skills plus a
prose linter.

## Decision
- **13 style ids** (direction, spec, guide, procedure, reference, public-help, legal, research,
  journal, brand-story, marketing, ui-copy, agent-facing), each with skills, house rules and checks.
- **Resolution:** front matter > folder README > section default > repo default.
- **Enforcement:** skills loaded explicitly when writing; Vale checks per path in the docs rung.
- **Humanizer** runs last and only on text published for people, never on specs or agent-facing text.
- **Every skill is vendored** with a `skills.lock`, from public upstreams with redistributable
  licences.
- **The skill library is its own module, Havamal** (Odin's "Sayings of the High One", which ends with
  the charms he knows), from v0. Our own skills will live there, each shipping only with an eval that
  shows it measurably helps.

## Result
Pending: Vale findings per style once the docs rung runs.

## Lessons
- Some style choices are requirements, not taste: GDPR Article 12 requires privacy information in
  clear and plain language.
- Agent-facing text is its own audience. "Humanizing" an `AGENTS.md` makes it vaguer, and every
  product built from that realm inherits the vagueness.
- Skills installed on one machine are invisible to sandboxed agents and to other operators. If the
  factory depends on a skill, the skill has to travel with the factory, pinned and reviewed. And check
  where a local copy came from: skills synced through an employer's plugin system may sit next to
  internal material that must never reach a public repo.

---
date: 2026-10-11
tags: [docs, writing, dogfooding]
status: resolved
post-candidate: yes
evidence: [../4-ways-of-working/writing-styles.md, "https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec-wording-review.md"]
---
## Challenge

Right after defining writing styles, the question came: do our own documents follow them? They
didn't. They were written before the standard existed, and nothing had checked them.

## Context

A mechanical scan found the spec with 51 of 258 sentences over its length limit and no RFC 2119
keywords at all; eight documents without front matter; research briefs with inconsistent analysis
markers; and a bug in the standard itself (image-generation prompts mapped to the marketing style,
which would have run a humanizer over prompts meant for a model).

## Options

Fix after the review, or run a style pass before it so the review happens once, on the final form.

## Decision

A style pass before review: mechanical fixes first (front matter, a new `prompt` style), then five
parallel rewrites, one per style family, each with the matching skill loaded and strict rules: no
heading, link, front-matter or fact changes. The spec rewrite listed every requirement whose meaning
might have shifted, for a human to confirm.

## Result

Spec: 16 of 412 sentences over the limit; 168 RFC 2119 keywords; 58 requirements listed for review.
No heading changed in 60 files; every link and anchor resolves. The pass also surfaced two
pre-existing errors, one of them from an earlier automated renumbering.

## Lessons

- A standard you don't apply to your own documents isn't a standard yet.
- These documents are what agents will copy. Loose requirement wording here would become loose
  requirements in every product's spec.
- Style rewrites of requirements are design-sensitive: turning "should" into MUST or SHOULD is a
  decision, so the rewrite must surface every such change for a human.

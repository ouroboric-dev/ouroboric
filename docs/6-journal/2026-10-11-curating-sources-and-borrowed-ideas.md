---
date: 2026-10-11
tags: [research, prior-art, merge, benchmark, routing, licensing]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/5-research/curation.md, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#45-the-merge-gate, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#46-typed-findings, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#11-benchmark-format-full-kit-later-as-mimir]
---
## Challenge

Build a curated list of learning sources, mainly open source, and find ideas worth bringing into
Yggdrasil. Starting point: super-board, a promising but little-known project.

## Context

We checked about 110 repositories live on GitHub (stars, activity, licence, archived or not). Several
well-known projects had moved, been archived or announced shutdowns, so stale links were a real risk.

## Options

Judge by popularity, or judge each project by what it teaches and what it would cost to reuse.

## Decision

Judge by substance, and treat stars as reach, not quality. super-board: don't depend on it (one
author, `curl | bash` install, auto-merge), but its merge gate and review design were worth taking.
Four ideas went into the v0 spec:

- **Merge gate:** lock, merge the latest base into the branch, re-run checks, merge pinned to the
  reviewed commit.
- **Typed findings:** stable ids across fix attempts, closed only with file:line proof; malformed data
  stops the loop instead of passing.
- **Harbor-compatible benchmarks:** a shared task layout and grading in a separate container after
  the agents stop.
- **Native headless protocols** (codex app-server, ACP next) and routing edges tagged `extracted`
  vs `inferred`.

## Result

Pending: the merge gate's catches and the findings' reopen rates will show up in the ledger.

## Lessons

- A small project can hold one excellent idea. Read the code, not the star count.
- Licences decide what you can borrow. Copying a helper from an AGPL project would oblige anyone
  hosting Yggdrasil to publish their source; source-available and unlicensed code is read-only too.
- "Green once" is not "green now": without a merge gate, a branch that passed against yesterday's
  `main` can land broken, and every later branch builds on the breakage.

---
date: 2026-10-19
tags: [graph, realms, architecture, voluspa]
status: resolved
post-candidate: yes
evidence: ["https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/changes/2026-10-19-voluspa/proposal.md", "voluspa-H02", "voluspa-H03", "run 20261019-184434-257049", "run 20261019-212556-8b365f"]
---
## Challenge

The lead realm, `midgard-react`, did seven jobs. It supplied the graph, the stage prompts, the reviewers'
prompts, the scratch sessions' stack and egress, the acceptance check and its stack, the routing threshold,
and the default realm of an unpinned leaf. A backend-only product, or a product with another frontend flavor,
had no graph to run.

## Context

The founder had decided that one graph serves all software, and that only the loop inside it is specific to a
stack. Phase 5a had already built the loader that hashes a realm from its committed files and records it in
`run.json`. Phase 5c's code read the lead realm in several places.

## Options

Keep the graph in the lead realm and add a second graph per flavor. Or move the graph and its prompts to one
new repo, and give each of the other jobs one clear owner.

## Decision

A new leaf, `voluspa`, holds a graph pack: `software`, with its graph and eight prompts. It loads like a realm,
so a run records its name, version and hash, and a resume refuses a graph whose hash changed. The project pins
the graph, and a run names it with `--graph`. A leaf's implementer, template and checks stay with the leaf's own
pinned realm. A graph states the Gungnir schema version it needs, and Odin refuses one it can't run before any
sandbox starts. Graphs have descriptive names; myth names stay with realms and components.

## Result

The prompts moved byte for byte. SHA-256 of each prompt at `midgard-react` `4d145f3` and in
`voluspa/software/prompts/`:

| File | Before | After |
| --- | --- | --- |
| design.md | 224ae13264b1269ef1486a54592e180b8b748c515777a8291ba26d4876482100 | 224ae13264b1269ef1486a54592e180b8b748c515777a8291ba26d4876482100 |
| spec.md | 5c5286064571747060480f778960f7c232bb6d2dbce7c2827899c9d7660d6ac4 | 5c5286064571747060480f778960f7c232bb6d2dbce7c2827899c9d7660d6ac4 |
| conformance.md | e6986545cf1485ded7be2e2b86181c8e2825909bddb28d2361ad274f9969552b | e6986545cf1485ded7be2e2b86181c8e2825909bddb28d2361ad274f9969552b |
| plan.md | a873bf018364077f67520ee4239297817cf13b0bafc3e89ad71309ced917d1e0 | a873bf018364077f67520ee4239297817cf13b0bafc3e89ad71309ced917d1e0 |
| reuse-review.md | 01fc1f38f21680e995473cd0be882665e4cd3639521a0b05b795913564de9c49 | 01fc1f38f21680e995473cd0be882665e4cd3639521a0b05b795913564de9c49 |
| reviewer-spec.md | df53bb0ac76f0c253a9e59b3bbd7a635d5498bab55fcc76476dcd8f441cf435e | df53bb0ac76f0c253a9e59b3bbd7a635d5498bab55fcc76476dcd8f441cf435e |
| reviewer-simplicity.md | e8438c2b44ad9f94d520d7a4e6b0663e9f661512f546c1c92eba231595546c83 | e8438c2b44ad9f94d520d7a4e6b0663e9f661512f546c1c92eba231595546c83 |
| reviewer-quality.md | 55c183ebbf64b4957acec2e79e9514271b77628cf743fa3e60d5e4d3c6f1bafc | 55c183ebbf64b4957acec2e79e9514271b77628cf743fa3e60d5e4d3c6f1bafc |

Then the same two-task run on the same project, before and after the change (H02 at `odin` `7b5248a`, H03 at
`odin` `bc973e3` with `--graph software`):

| | H02 (before) | H03 (after) |
| --- | --- | --- |
| Status | done, 2/2 tasks, both loops at attempt 1, 0 findings | the same |
| Header | `realm: midgard-react 0.1.0 (graph 0.1.0)` | `graph: software 0.1.0` |
| Usage | 8000 in, 800 out, 16 turns, $0 | the same |
| Acceptance, both moves | exit 0 | exit 0, run by `midgard-react` |

The two snapshot sandboxes used the same four images in both runs. The run's behaviour did not change; only
its header and the sandbox names did. The runs cost $0, so this shows the wiring is intact, not that the factory
is better.

## Lessons

Give each job one owner before a second flavor needs it. Prove a move with hashes of the moved files and a
before-and-after run, not by reading the diff.

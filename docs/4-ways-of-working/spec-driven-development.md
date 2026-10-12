---
title: Spec-driven development
status: accepted
date: 2026-10-12
related: [docs-standard.md, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/design/2026-10-11-yggdrasil-v0-design.md]
---

# Spec-driven development

This document describes how work goes from an idea to merged, verified code, for **every Ouroboric
product and every product they build**. **Asgard**, the company factory, runs tier 0 (kickstart).
**Yggdrasil**, the software factory, runs tiers 1–3. The process doesn't depend on any tool: Spec Kit,
OpenSpec, BMAD, Superpowers or native prompts are interchangeable ways to produce the artifacts it defines.

## 1. Principles

1. **Humans approve direction. Deviations from approved direction stop. Building within it is
   automatic.** Every approval point follows from this rule.
2. **Ceremony scales with the size of the change.** A bug fix doesn't need a design doc.
3. **The process defines artifacts, not tools.** Any tool may produce them; Odin checks that what it
   produced conforms.
4. **Specs stay alive.** A change in behaviour carries its spec change in the same merge.
5. **Checks, not promises.** Readiness, conformance, test-first and drift are checked mechanically
   wherever possible.

## 2. The layers

| Layer | Question it answers | Typical author | Approval |
|---|---|---|---|
| **Charter** (once per product) | *Where* are we going and by which rules? Vision, mission, principles, users and problems, north-star measures, boundaries | the operator, brainstorming with an agent | **a human, in every mode by default** (override: `gates: { charter: auto }`) |
| **Design doc** (like a PRD) | *What* are we building, for *whom*, and *why*? Scope, success criteria, non-goals | the product role: a human brainstorming with an agent | **a human, in every mode by default.** It decides what gets built. Overriding this needs an explicit `gates: { design: auto }` |
| **Spec** (like an RFC) | *How* will engineering deliver the design? Architecture, contracts, data model, acceptance criteria per feature, decisions | an engineering agent | **automatic if it conforms to the design doc.** A design-conformance reviewer checks it; a deviation stops the run. You can set key-points mode to always stop (`spec: stop`) |
| **Plan and tasks** | In what order, in which repo, proven by which tests? | an engineering agent | automatic in every mode except step-by-step |

The charter bounds every design doc. A **charter-conformance check** stops a design doc that drifts
from it (for example, a design doc for payments when the charter's boundaries rule out payments). The
charter's principles also become `AGENTS.md` invariants in every repo of the product.

The design doc is the handover from product to engineering. The spec must stay within it. When
engineering finds that the design is wrong or incomplete, the run stops at `design` with a proposed
amendment rather than quietly building something else.

## 3. Tiers

| Tier | Example | Artifacts | Human approval |
|---|---|---|---|
| **0: kickstart** | a new product | charter, shape, brand seed, roadmap, then milestone 1's design doc (§3.1) | `charter`, then `design` |
| **1: fix or chore** | a bug, a dependency bump, a docs fix | one task: acceptance criterion and a **failing test that reproduces it** | none beyond approving the issue itself (it is the direction) |
| **2: small change** | a new gallery setting | a **change proposal** (acts as a mini design doc, §5) and 1–3 tasks | `design` |
| **3: initiative** | a new product, a new realm, payments | design doc → spec → plan → tasks | `design` |

When in doubt, use the higher tier. If hidden complexity shows up during the work, move up a tier and
stop at the matching approval point.

### 3.1 Tier 0: kickstarting a company or a product

Every company and every product starts here, once, and Asgard runs it. (In the naming story, every realm
begins in **Ginnungagap**, the void before creation; Ginnungagap is also the name of Asgard's kickstart
graph.)

- A **company kickstart** produces the company umbrella: `1-company/charter.md` (vision, mission,
  principles, values and culture, portfolio, north star, boundaries), roadmap, brand seed, legal
  basics, and a **readiness assessment** against Asgard's checklist.
- A **product kickstart** happens inside an existing company. The product charter must conform to the
  company charter. The table below lists its steps.
- The company's **readiness levels** gate what follows: *ready to build* before the first spec,
  *ready to launch* before `deploy-prod`, *ready to promote* before public promotion.

| Step | Produces | Approval |
|---|---|---|
| 1. Intent and research | brainstorm notes; research briefs in `docs/5-research/` | — |
| 2. Charter | `docs/1-product/charter.md` | `charter` (human) |
| 3. Shape | realm(s), the repo tree (umbrella and leaves), org, visibility and hosting target, recorded in the charter's boundaries; the umbrella scaffolded to the [docs standard](docs-standard.md), with `AGENTS.md` invariants derived from the principles | — |
| 4. Brand seed | name and story theme in `docs/7-branding/story/`; a minimal visual identity (palette, typography, logo) in `docs/7-branding/identity/`, which readiness requires before building | `charter` (approved together) |
| 5. Roadmap | `docs/1-product/roadmap.md`: ordered milestones | `charter` (approved together) |
| 6. First design doc | milestone 1's design doc; from here the regular tier-3 flow | `design` |

**Benchmark runs skip tier 0:** a frozen benchmark brief stands in for charter and design intent, so
runs stay comparable.

## 4. Stages and approval points

<!-- diagram: assets/diagrams/sdd-flow.mmd -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/diagrams/rendered/sdd-flow.dark.svg">
  <img alt="Spec-driven development: charter and design doc need human approval; the spec is approved automatically unless it deviates; plan, build, merge gate, living spec and journal follow automatically" src="../assets/diagrams/rendered/sdd-flow.svg">
</picture>

```
(tier 0 once: intent ─► charter ─► [charter] ─► shape, brand seed, roadmap)
intent ─► design doc ─► charter-conformance check ─► [design] ─► spec ─► conformance review ─► [spec] ─► plan + reuse review
       ─► tasks + DoR check ─► [plan] ─► implement (TDD, fresh session per task)
       ─► check ladder + reviewers (typed findings) ─► [feature] ─► merge gate ─► [merge]
       ─► pointer move ─► [pointer | pointer-contract] ─► update living spec ─► journal
```

| Approval point | step-by-step | key-points (default) | unattended |
|---|---|---|---|
| `charter` | stop | stop | stop (default; explicit override only) |
| `design` | stop | stop | stop (default; explicit override only) |
| `spec` | stop | auto, stop on deviation (option: `spec: stop`) | auto, stop on deviation |
| `plan`, `feature`, `merge`, `pointer` | stop | auto | auto |
| `pointer-contract` | stop | auto if the contract change was in the approved spec; stop if not | same, but the task is blocked and the rest continue |
| hard approval points | stop | stop | stop |

Hard approval points (`deploy-prod`, `store-submit`, `real-secrets-or-user-data`, `budget-cap`,
`external-input`, `policy-violation`, `shrink-guard`, and `guardrail-change` once self-hosting starts)
always stop, and no configuration can turn them off. The merge gate's mechanical steps (lock, update, re-check,
merge pinned to the reviewed commit) run on every merge whether or not a human approves it.

## 5. Canonical artifacts

These artifacts are part of the Gungnir contract. Every planning strategy must produce them. Odin
rejects output that doesn't conform.

### Charter — `docs/1-product/charter.md`

One per product. Sections: vision; mission; principles; users and problems (may link `users.md`);
north-star measures; boundaries (product-level non-goals and constraints: budget, compliance, realm,
hosting). The charter changes rarely, and only through the `charter` approval point.

### Design doc — `docs/1-product/design/YYYY-MM-DD-<slug>.md`

Links the charter in `related`. Front matter (`title`, `status`, `date`, `related`) and sections:
summary; goals, non-goals and success criteria; context and constraints; the product or feature
described at user level; decisions (`**Decided YYYY-MM-DD:** …`); open questions.

### Spec — `docs/2-engineering/specs/YYYY-MM-DD-<slug>.md`

Links its design doc in `related`. Sections: summary; architecture and components; interfaces and
contracts; data model; acceptance criteria per feature; security considerations; testing approach;
decisions; deviations from the design doc (must be empty for automatic approval).

### Plan and tasks — `docs/2-engineering/plans/YYYY-MM-DD-<slug>/`

`plan.md` (order, dependencies, risks) and `tasks.md`. Every task has:

| Field | Rule |
|---|---|
| `id` | stable, feature-scoped (`<plan>-T001`) |
| acceptance criteria | testable checkboxes |
| named test | file and test name that will prove it |
| `layer` | which leaf repo |
| `size` | S < 100 changed lines, M 100–400, L means split it |
| depends on | task ids |

The **Definition of Ready** check rejects any task missing one of these, and sends L-sized tasks back
for splitting.

### Change proposal — `docs/2-engineering/changes/YYYY-MM-DD-<slug>/`

Use a change proposal to change something that already exists (OpenSpec-style):

- `proposal.md`: why, what changes, impact (from the impact index);
- `delta.md`: the spec delta, as **added**, **modified** and **removed** requirements against the
  living spec;
- `tasks.md`: as above.

When the change merges, Odin folds the delta into the living spec (`docs/2-engineering/system/`) and
moves the folder to `changes/archive/`.

### Living spec — `docs/2-engineering/system/`

How the system works **today**. Dated design docs and specs record decisions, and nobody edits them
after acceptance. The living spec is the current truth, and it changes only through deltas.

## 6. Keeping the spec alive

"Changing code without updating the spec" is the most common way spec-driven development fails.
These controls prevent it:

- **Same-merge rule:** a change in behaviour includes its delta in the same merge. The
  spec-compliance reviewer raises a finding for a behaviour change with no delta.
- **Traceability:** commits carry task ids. The doc↔code index shows code that no task explains and
  tasks that no code implements.
- **Decisions are searchable:** `**Decided …**` lines feed the decisions index, so agents look up why
  something was chosen instead of re-arguing it.

## 7. Implementation and review

- **One fresh agent session per task.** Each session reads `AGENTS.md`, `progress.md`, its task and
  the routing summary.
- **Test first:** the task's named test must fail on the parent commit, then pass.
- **Check ladder** per realm, then three read-only reviewers in order: **spec compliance**, **code
  quality**, **simplicity**. Reviewers report typed findings with stable ids. A finding closes only with
  proof.
- **Merge gate** on every merge and pointer move.

## 8. Strategies: where tools plug in

| Strategy | Stage | Options | Status |
|---|---|---|---|
| **planning** | design doc → spec → plan → tasks | native (v0); Spec Kit; OpenSpec; BMAD | v0 native; others benchmarked later |
| **reuse review** | plan | Ponytail (`ponytail-review` on the plan): flags new dependencies or abstractions where the standard library or existing code already does the job | v0 |
| **simplicity reviewer** | check ladder | Ponytail (`ponytail-review`) | v0 |
| **cleanup** (against Nidhogg) | periodic, per leaf | Ponytail (`ponytail-audit`) | later |

Rules for third-party strategies:

- **Invoke explicitly, never rely on auto-triggering.** In an independent JetBrains test, Ponytail
  activated on its own in zero of ten sessions.
- **Vendor a pinned, reviewed copy** (recorded in `skills.lock`; see
  [writing styles §5](writing-styles.md#5-vendored-skills)). Feed the skill's instructions to the agent as
  part of its prompt. Don't install plugin hooks. Otherwise, a compromised upstream update would run
  inside every session of every run.
- **Benchmark every strategy.** Run the same brief with and without it, and compare the hidden score,
  lines of code, tokens and cost.

## 9. Using the process before the factory exists (stage 0)

Until Yggdrasil can build itself, humans and an interactive agent follow the same process by hand:

1. Kickstart (tier 0) by brainstorming together. For Yggdrasil, this happened in the 2026-10-10/11
   sessions and was recorded retroactively: the [charter](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/charter.md), the
   [roadmap](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/roadmap.md) and the [naming story](../7-branding/story/naming-and-mythology.md).
2. Write milestone 1's design doc and its engineering spec as separate documents:
   [v0 design doc](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/design/2026-10-11-yggdrasil-v0-design.md) and
   [v0 spec](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md).
3. Write the implementation plan and tasks into `docs/2-engineering/plans/`.
4. Implement test-first, one task per session, with reviews and the same commit conventions.
5. Record challenges in the journal.

No document is exempt: the factory's own founding documents follow the same structure as any
product's.

## 10. Self-hosting

Yggdrasil builds itself in stages:

| Stage | Who builds Yggdrasil | Needs |
|---|---|---|
| 0 | a human with an interactive agent | this process, followed by hand |
| 1 | Yggdrasil builds one of its own features | the change graph, a Go realm, `guardrail-change` |
| 2 | Yggdrasil improves itself from benchmark results | the benchmark kit (Mimir) and a release regression gate |

A factory that edits itself can weaken its own guardrails. For example, an agent "fixes" a flaky test
by deleting an escape-attempt test. The next version ships with that hole. That weaker version then
reviews and builds the version after it. Rules:

- **Never build in place.** The factory that runs is always the last released version pinned in L0,
  never the working copy being changed.
- **`guardrail-change` is a hard approval point.** Any change to approval points and modes, sandbox
  hardening, policies, ledger integrity or the escape-attempt suite stops for a human in every mode.
- **The security suite can't shrink silently.** If there are fewer escape-attempt or gate tests than
  before, the shrink guard trips.
- **No release that regresses on benchmarks.**

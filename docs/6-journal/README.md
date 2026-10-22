# Journal

The journey journal: one entry per challenge met while building Yggdrasil, with the options we
considered, what we chose, and the measured result. In the naming story these entries are the
**sagas**; a future content component (**Bragi**) will turn them into blog posts. Spec:
[§13.5](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#105-journey-journal).

## Checking

`scripts/journal-check.sh` reads this folder and fails when an entry breaks the rules above: a missing key, a status that
is not `open`, `resolved` or `abandoned`, sections out of order, a resolved entry with no evidence or a Result that is still
"pending", an entry that the index below does not list or lists differently, or a raw ledger line. An entry that records a
change to the factory carries the tag `factory-change`; once it is resolved, its Result cites the before and after with
`ygg metrics --compare <runA> <runB>` and names both run ids (design doc §2.3, criterion 6).

## Entries

| Date | Entry | Tags | Status | Post candidate |
| --- | --- | --- | --- | --- |
| 2026-10-10 | [autonomy modes and hard gates](2026-10-10-autonomy-modes-and-hard-gates.md) | graph, gates, safety, cost | open | yes |
| 2026-10-10 | [go vs pekko](2026-10-10-go-vs-pekko.md) | stack, cloud, architecture | open | yes |
| 2026-10-10 | [no lock in](2026-10-10-no-lock-in.md) | harness, adapters, models | open | yes |
| 2026-10-10 | [own orchestrator not a framework](2026-10-10-own-orchestrator-not-a-framework.md) | graph, architecture, frameworks | open | yes |
| 2026-10-10 | [spec kit and superpowers](2026-10-10-spec-kit-and-superpowers.md) | graph, spec-driven, measurement | open | yes |
| 2026-10-10 | [what harness loop graph mean](2026-10-10-what-harness-loop-graph-mean.md) | research, harness, loop, graph | resolved | yes |
| 2026-10-10 | [why build a factory](2026-10-10-why-build-a-factory.md) | purpose, scope | open | yes |
| 2026-10-11 | [devcontainers and the host escape](2026-10-11-devcontainers-and-the-host-escape.md) | harness, sandbox, security | open | yes |
| 2026-10-11 | [first product client gallery](2026-10-11-first-product-client-gallery.md) | product, benchmark, security | open | yes |
| 2026-10-11 | [hosting egress decides cost](2026-10-11-hosting-egress-decides-cost.md) | infra, cost, security | open | yes |
| 2026-10-11 | [identities orgs and open source](2026-10-11-identities-orgs-and-open-source.md) | security, github, open-source | open | yes |
| 2026-10-11 | [journal from day one](2026-10-11-journal-from-day-one.md) | process, promotion | resolved | no |
| 2026-10-11 | [naming the tree](2026-10-11-naming-the-tree.md) | naming, branding, modularity | resolved | yes |
| 2026-10-11 | [progress tracking](2026-10-11-progress-tracking.md) | observability, tracking | open | no |
| 2026-10-11 | [routing needs a bench](2026-10-11-routing-needs-a-bench.md) | routing, measurement | open | yes |
| 2026-10-11 | [umbrella tree and git hooks](2026-10-11-umbrella-tree-and-git-hooks.md) | graph, topology, security, validation | open | yes |
| 2026-10-11 | [web stack react go vs nextjs](2026-10-11-web-stack-react-go-vs-nextjs.md) | stack, web, security, benchmark | open | yes |
| 2026-10-11 | [curating sources and borrowed ideas](2026-10-11-curating-sources-and-borrowed-ideas.md) | research, prior-art, merge, benchmark, routing, licensing | open | yes |
| 2026-10-11 | [sdd process and docs standard](2026-10-11-sdd-process-and-docs-standard.md) | process, spec-driven, docs, self-hosting, simplicity | open | yes |
| 2026-10-11 | [kickstart and the charter](2026-10-11-kickstart-and-the-charter.md) | process, kickstart, charter, docs | resolved | yes |
| 2026-10-11 | [writing styles and vendored skills](2026-10-11-writing-styles-and-vendored-skills.md) | docs, writing, skills, supply-chain | open | yes |
| 2026-10-11 | [two factories and a company](2026-10-11-two-factories-and-a-company.md) | architecture, company, asgard, readiness | open | yes |
| 2026-10-11 | [the style guide applied to itself](2026-10-11-the-style-guide-applied-to-itself.md) | docs, writing, dogfooding | resolved | yes |
| 2026-10-11 | [diagrams as code](2026-10-11-diagrams-as-code.md) | docs, diagrams, security, tooling | resolved | yes |
| 2026-10-11 | [choosing a licence](2026-10-11-choosing-a-licence.md) | licensing, open-source, publishing | resolved | yes |
| 2026-10-11 | [first publish](2026-10-11-first-publish.md) | publishing, security, github, tooling | resolved | yes |
| 2026-10-11 | [choosing the palette](2026-10-11-choosing-the-palette.md) | brand, design, accessibility | resolved | yes |
| 2026-10-11 | [choosing the typography](2026-10-11-choosing-the-typography.md) | brand, design, typography, accessibility | resolved | yes |
| 2026-10-11 | [diagrams in the design language](2026-10-11-diagrams-in-the-design-language.md) | brand, diagrams, accessibility, tooling | resolved | yes |
| 2026-10-12 | [designing the logo](2026-10-12-designing-the-logo.md) | brand, design, logo, accessibility | resolved | yes |
| 2026-10-19 | [a definition of done for realms](2026-10-19-a-definition-of-done-for-realms.md) | realms, readiness, ci, process | resolved | yes |
| 2026-10-19 | [one graph for every run](2026-10-19-one-graph-for-every-run.md) | graph, realms, architecture, voluspa | resolved | yes |
| 2026-10-20 | [choosing the reviewer model](2026-10-20-choosing-the-reviewer-model.md) | models, review, routing, measurement, cost, sandbox | open | yes |

## When to write an entry

- every design decision worth explaining to someone else;
- every surprising failure;
- every harness change made because of a run (cite before/after runs with `ygg metrics --compare`);
- every benchmark milestone.

Record a decision as soon as you make it, with `status: open` and the result marked pending. Update
the entry when the result arrives.

## Template

Copy into `YYYY-MM-DD-<slug>.md`:

```markdown
---
date: YYYY-MM-DD
tags: [harness, loop, graph, routing, security, cost, …]
status: open | resolved | abandoned
post-candidate: yes | no
evidence: [run ids, commits, spec sections, research briefs]
---
## Challenge
What went wrong, or what had to be decided.

## Context
What we knew; constraints.

## Options
What we considered, with trade-offs.

## Decision
What we chose and why.

## Result
Measured outcome (metrics deltas from `ygg metrics --compare`), or "Pending: <what will tell us>".

## Lessons
What we would tell someone building their own factory.
```

## Scrubbing rules

This repo will be public, and blog posts are effectively permanent: search engines and archives keep
copies after edits.

- Never include secrets, tokens or keys, even expired ones.
- Never include private product names, private code, client data, or raw transcripts and ledger
  excerpts from private runs. Record those lessons in the private L0 instance first; bring only an
  anonymised summary and aggregate numbers here.
- Link to private evidence by run id only; don't paste it.
- `gitleaks` runs on this repo like any other.

---
title: Ready to build — assessment 2026-10-11
status: draft
date: 2026-10-11
related: [../charter.md, "https://github.com/ouroboric-dev/asgard/blob/main/templates/readiness/checklist.md"]
style: direction
---

# Ready to build — assessment 2026-10-11

**Bottom line: ready to build (re-run on 2026-10-14).** All 21 items are met. The first assessment
(2026-10-11) found 14 met, 5 partial and 2 missing; the reviews and the Phase 0 tasks of the
[v0 plan](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/plans/2026-10-12-yggdrasil-v0/plan.md)
closed the rest. When the founder merges this re-run, the gate is passed and Phase 1 may start.

Scope: Ouroboric (company) and Yggdrasil v0 (first product to build). Checklist: Asgard's
[readiness checklist](https://github.com/ouroboric-dev/asgard/blob/main/templates/readiness/checklist.md),
level 1.

## Summary

<!-- diagram: assets/diagrams/readiness-levels.mmd -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../assets/diagrams/rendered/readiness-levels.dark.svg">
  <img alt="Readiness levels: kickstart, then ready to build before spec and build, ready to launch before deploy-prod, ready to promote before promotion" src="../../assets/diagrams/rendered/readiness-levels.svg">
</picture>

Of 21 items, 21 are met, 0 are partial and 0 are missing (re-run on 2026-10-14).

| Status | Count | Items |
|---|---|---|
| met | 21 | RB-01 to RB-21 |
| partial | 0 | — |
| missing | 0 | — |

## Suggested review order

Review in this order to close the most items fastest. This assessment doubles as the review guide.

1. **Company charter** (RB-01): reword the vision and mission; everything else conforms to it.
2. **Yggdrasil product charter** (RB-02), then the **v0 design doc** (RB-03) and **roadmaps** (RB-04).
3. **Standards** (RB-15): spec-driven development, docs standard, writing styles.
4. **v0 engineering spec**: not a readiness item itself, but RB-18 (the plan) depends on it.
5. **Decisions only you can make**: budgets (RB-13), name checks
   (RB-06).

## Items

| ID | Question | Status | Evidence | To close |
|---|---|---|---|---|
| RB-01 | Company charter accepted? | met | [Ouroboric charter](../charter.md), accepted on 2026-10-12 with the founder's vision and mission | — |
| RB-02 | Product charter accepted and conforming? | met | [Yggdrasil](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/charter.md) and [Asgard](https://github.com/ouroboric-dev/asgard/blob/main/docs/1-product/charter.md) product charters, accepted on 2026-10-12; both missions carry the ouroboric property and their principles inherit from the company charter | — |
| RB-03 | Milestone 1 design doc accepted? | met | [v0 design doc](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/design/2026-10-11-yggdrasil-v0-design.md), accepted on 2026-10-12, with a measured self-improvement as success criterion 7 | — |
| RB-04 | Roadmaps written? | met | [company roadmap](../roadmap.md) and [Yggdrasil roadmap](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/roadmap.md), accepted on 2026-10-12; self-hosting stage 1 requires the change graph, the Go realm and `guardrail-change` first | — |
| RB-05 | Principles as `AGENTS.md` invariants? | met | `AGENTS.md` with an `## Invariants` section in the umbrellas ([ouroboric #19](https://github.com/ouroboric-dev/ouroboric/pull/19), [yggdrasil #10](https://github.com/ouroboric-dev/yggdrasil/pull/10), [asgard #5](https://github.com/ouroboric-dev/asgard/pull/5)), derived from the accepted charters; every component repo's `AGENTS.md` links the yggdrasil invariants and defines none of its own; `check-repos.sh --check agents` passes on all repos (v0-T006) | — |
| RB-06 | Name checked? | met | [name checks](../../5-research/2026-10-12-name-checks.md), 2026-10-12: `ouroboric.dev` owned; `ouroboric` free on npm, PyPI, crates.io and Homebrew (taken on Docker Hub; official images go to `ghcr.io/ouroboric-dev`); trademark screening found no "Ouroboric" mark (nearest: OROBOROUS, status unknown); product names used under the Ouroboric umbrella | formal trademark search before launch (Asgard checklist RL-08); founder claims `ouroboric` on npm and PyPI (crates.io skipped: no Rust planned) |
| RB-07 | Brand seed written? | met | [naming and mythology](../../7-branding/story/naming-and-mythology.md); [logo prompts](../../7-branding/prompts/nano-banana-logo-prompts.md) | — |
| RB-08 | Licence chosen for public work? | met | [licence map](../legal/README.md): AGPL-3.0 factory code, MIT copied templates, CC BY 4.0 docs; [trademarks](../../../TRADEMARKS.md) | — |
| RB-09 | Contribution terms in place? | met | read-only publication: code of conduct, security policy and contributing guide in the organisation's `.github` repository; a contributor licence agreement is required before the first outside contribution ([legal](../legal/README.md#contributions)) | — |
| RB-10 | Ownership clear? | met | confirmed by the founder on 2026-10-11 | — |
| RB-11 | Shape decided? | met | company umbrella `ouroboric` with products `yggdrasil` (umbrella with `gungnir`, `odin`, `gleipnir`, `jormungandr`, `havamal`, `realm-web`) and `asgard`; local git only; hosting target for products in the [v0 spec](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#93-infrastructure-target) | — |
| RB-12 | Repos exist and follow the docs standard? | met | the six component repos created protected by the founder with `create-repo.sh` ([ouroboric #22](https://github.com/ouroboric-dev/ouroboric/pull/22), v0-H04), scaffolded (`gungnir`, `odin`, `gleipnir`, `jormungandr`, `realm-web`, `havamal`, each PR #1) and wired into the `yggdrasil` umbrella as submodules with a `go.work` ([yggdrasil #14](https://github.com/ouroboric-dev/yggdrasil/pull/14), [#16](https://github.com/ouroboric-dev/yggdrasil/pull/16)); existing repos brought to standard with `setup-repo.sh` (v0-T005); the benchmark repo [`mimir`](https://github.com/ouroboric-dev/mimir) is public and standard; `check-repos.sh` (all checks, all repos) exits 0 on 2026-10-15 | — |
| RB-13 | Budgets and caps set? | met | [budget](../budget.md) decided on 2026-10-12, subscription changed on 2026-10-13 ([#26](https://github.com/ouroboric-dev/ouroboric/pull/26)): the founder's personal Claude subscription started for Ouroboric, an OpenRouter key capped at $25 a month for open-weight models, default caps of 400 turns, 8M tokens and $5 per run and 1,000 turns, 20M tokens and $10 per day; the founder created the factory's `claude setup-token` token and the capped OpenRouter key, kept outside every repo in a file readable only by the founder (v0-H01, 2026-10-14) | — |
| RB-14 | Credentials and secret scanning? | met | factory credentials only in a file outside every repo, mode 600 (v0-H01); agents reach GitHub only as the `ouroboric-pr-bot` GitHub App with one-hour tokens and no admin rights, with no other GitHub login or SSH key in their environment ([#20](https://github.com/ouroboric-dev/ouroboric/pull/20), v0-H03); `gitleaks` v8.30.1 as a pre-commit hook in every repo ([#25](https://github.com/ouroboric-dev/ouroboric/pull/25) and one PR per repo), history scans of every repo clean, push protection on every repo (v0-T014) | — |
| RB-15 | Standards accepted? | met | [spec-driven development](../../4-ways-of-working/spec-driven-development.md), [docs standard](../../4-ways-of-working/docs-standard.md), [writing styles](../../4-ways-of-working/writing-styles.md) and [diagrams](../../4-ways-of-working/diagrams.md), accepted on 2026-10-12 | — |
| RB-16 | Research recorded? | met | [Yggdrasil research](https://github.com/ouroboric-dev/yggdrasil/tree/main/docs/5-research): six briefs, cited | — |
| RB-17 | Journal started? | met | [journal](../../6-journal/README.md): 26 entries | — |
| RB-18 | Implementation plan accepted? | met | [v0 implementation plan](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/plans/2026-10-12-yggdrasil-v0/plan.md), accepted by the founder's merge of [yggdrasil #8](https://github.com/ouroboric-dev/yggdrasil/pull/8) on 2026-10-12; Phase 0's tasks in full, later phases' tasks written just in time | — |
| RB-19 | Technical risks identified, tested first? | met | [sandbox spike report](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/5-research/2026-10-12-sandbox-spike.md) ([yggdrasil #11](https://github.com/ouroboric-dev/yggdrasil/pull/11), v0-T001 to v0-T003): rootless engine on the Podman machine with the instance tree bind-mounted under `/mnt/wsl`, host registry credentials kept out of pulls; repo hooks and project MCP servers blocked on subscription auth with `--setting-sources user --strict-mcp-config`; OpenRouter `data_collection: deny` and `zdr: true` verified on a real call; per-container resource limits recorded as an accepted v0 gap; humanizer's licence deferred (marketing text is out of v0's scope) | — |
| RB-20 | Success measure fixed in advance? | met | v0 success criteria in the [design doc §2.3](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/design/2026-10-11-yggdrasil-v0-design.md#23-success-criteria); the brief was frozen in v0-H02, before any factory run, as [`mimir/client-gallery-lite`](https://github.com/ouroboric-dev/mimir/tree/main/client-gallery-lite) task version 4.0.0, SHA-256 `bd4b2c7aaf532d51acb3a7edfd5b193d368db8445093b7a24cd80b7ee24d8319`; the hidden suite (29 scenarios) was written by the founder from the brief alone and is kept in a private repo the pr-bot can't reach | — |
| RB-21 | Minimal visual identity defined? | met | [identity](../../7-branding/identity/README.md): palette (Midnight with International Orange, all pairs WCAG AA), typography (Cinzel, Fjalla One, Literata, Inter, JetBrains Mono, runic ornament, all under the OFL), diagrams in the palette and Inter in light and dark, and the [logo](../../7-branding/identity/logo/README.md): icon, Cinzel wordmark, light and dark versions, favicon and app icons, under the trademark policy | — |

## Next assessment

Re-run on 2026-10-14 by v0-T015: every item met, as expected after the review and Phase 0. The next
assessment is "ready to launch", before the first production deployment.

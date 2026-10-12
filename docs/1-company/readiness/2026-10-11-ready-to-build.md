---
title: Ready to build — assessment 2026-10-11
status: draft
date: 2026-10-11
related: [../charter.md, "https://github.com/ouroboric-dev/asgard/blob/main/templates/readiness/checklist.md"]
style: direction
---

# Ready to build — assessment 2026-10-11

**Bottom line: not ready to build yet, as expected at this stage.** Direction, research and process
are drafted and waiting for review. The blocking gaps are the reviews themselves, credentials and caps,
and the implementation plan. Nothing here needs new design work; most
gaps close through review and a few setup tasks.

Scope: Ouroboric (company) and Yggdrasil v0 (first product to build). Checklist: Asgard's
[readiness checklist](https://github.com/ouroboric-dev/asgard/blob/main/templates/readiness/checklist.md),
level 1.

## Summary

<!-- diagram: assets/diagrams/readiness-levels.mmd -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../assets/diagrams/rendered/readiness-levels.dark.svg">
  <img alt="Readiness levels: kickstart, then ready to build before spec and build, ready to launch before deploy-prod, ready to promote before promotion" src="../../assets/diagrams/rendered/readiness-levels.svg">
</picture>

Of 21 items, 14 are met, 5 are partial and 2 are missing.

| Status | Count | Items |
|---|---|---|
| met | 14 | RB-01, RB-02, RB-03, RB-04, RB-06, RB-07, RB-08, RB-09, RB-10, RB-11, RB-15, RB-16, RB-17, RB-21 |
| partial | 5 | RB-12, RB-13, RB-14, RB-19, RB-20 |
| missing | 2 | RB-05, RB-18 |

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
| RB-05 | Principles as `AGENTS.md` invariants? | missing | no `AGENTS.md` exists in any repo yet | write them as the first plan task, derived from the accepted charters |
| RB-06 | Name checked? | met | [name checks](../../5-research/2026-10-12-name-checks.md), 2026-10-12: `ouroboric.dev` owned; `ouroboric` free on npm, PyPI, crates.io and Homebrew (taken on Docker Hub; official images go to `ghcr.io/ouroboric-dev`); trademark screening found no "Ouroboric" mark (nearest: OROBOROUS, status unknown); product names used under the Ouroboric umbrella | formal trademark search before launch (Asgard checklist RL-08); founder claims `ouroboric` on npm and PyPI (crates.io skipped: no Rust planned) |
| RB-07 | Brand seed written? | met | [naming and mythology](../../7-branding/story/naming-and-mythology.md); [logo prompts](../../7-branding/prompts/nano-banana-logo-prompts.md) | — |
| RB-08 | Licence chosen for public work? | met | [licence map](../legal/README.md): AGPL-3.0 factory code, MIT copied templates, CC BY 4.0 docs; [trademarks](../../../TRADEMARKS.md) | — |
| RB-09 | Contribution terms in place? | met | read-only publication: code of conduct, security policy and contributing guide in the organisation's `.github` repository; a contributor licence agreement is required before the first outside contribution ([legal](../legal/README.md#contributions)) | — |
| RB-10 | Ownership clear? | met | confirmed by the founder on 2026-10-11 | — |
| RB-11 | Shape decided? | met | company umbrella `ouroboric` with products `yggdrasil` (umbrella with `gungnir`, `odin`, `gleipnir`, `jormungandr`, `havamal`, `realm-web`) and `asgard`; local git only; hosting target for products in the [v0 spec](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#93-infrastructure-target) | — |
| RB-12 | Repos exist and follow the docs standard? | partial | published on 2026-10-11: [`.github`](https://github.com/ouroboric-dev/.github), [`ouroboric`](https://github.com/ouroboric-dev/ouroboric), [`yggdrasil`](https://github.com/ouroboric-dev/yggdrasil), [`asgard`](https://github.com/ouroboric-dev/asgard), all public with secret scanning, push protection, private vulnerability reporting and a protected `main`; the component repos (`gungnir`, `odin`, `gleipnir`, `jormungandr`, `havamal`, `realm-web`) don't exist yet | create the component repos with the first plan tasks |
| RB-13 | Budgets and caps set? | partial | [budget](../budget.md) decided on 2026-10-12: a dedicated personal Claude subscription for the factory, an OpenRouter key capped at $25 a month, default caps of 400 turns, 8M tokens and $5 per run and 1,000 turns, 20M tokens and $10 per day | founder buys the dedicated subscription and creates the capped OpenRouter key (outside every repo) |
| RB-14 | Credentials and secret scanning? | partial | no secrets in any repo (manual scans of the journal); dedicated tokens and `gitleaks` designed, not set up | create a `claude setup-token` token for the factory only; add `gitleaks` as a pre-commit check in each repo |
| RB-15 | Standards accepted? | met | [spec-driven development](../../4-ways-of-working/spec-driven-development.md), [docs standard](../../4-ways-of-working/docs-standard.md), [writing styles](../../4-ways-of-working/writing-styles.md) and [diagrams](../../4-ways-of-working/diagrams.md), accepted on 2026-10-12 | — |
| RB-16 | Research recorded? | met | [Yggdrasil research](https://github.com/ouroboric-dev/yggdrasil/tree/main/docs/5-research): six briefs, cited | — |
| RB-17 | Journal started? | met | [journal](../../6-journal/README.md): 26 entries | — |
| RB-18 | Implementation plan accepted? | missing | none yet; [plans folder](https://github.com/ouroboric-dev/yggdrasil/tree/main/docs/2-engineering/plans) is empty. RB-03 and the [v0 spec](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md) are accepted (2026-10-12), so the plan is unblocked | write the plan |
| RB-19 | Technical risks identified, tested first? | partial | listed in [v0 spec §16](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#16-open-items-and-first-spike) (devcontainer + rootless Podman, `--bare` with subscription auth, OpenRouter privacy settings, humanizer licence; and whether the container engine is rootless, since this machine's Podman uses a Podman Desktop machine's rootful socket; that the Podman VM can't mount WSL paths; and that host registry credentials leak into image pulls) | make the throwaway spike the plan's first task |
| RB-20 | Success measure fixed in advance? | partial | v0 success criteria in the [design doc §2.3](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/design/2026-10-11-yggdrasil-v0-design.md#23-success-criteria); the client gallery brief exists; the hidden suite doesn't | freeze the brief and write the hidden suite before the first factory run, without looking at any factory output |
| RB-21 | Minimal visual identity defined? | met | [identity](../../7-branding/identity/README.md): palette (Midnight with International Orange, all pairs WCAG AA), typography (Cinzel, Fjalla One, Literata, Inter, JetBrains Mono, runic ornament, all under the OFL), diagrams in the palette and Inter in light and dark, and the [logo](../../7-branding/identity/logo/README.md): icon, Cinzel wordmark, light and dark versions, favicon and app icons, under the trademark policy | — |

## Next assessment

Re-run this assessment after the review. Expected results after review and setup: RB-01–04 and
RB-15 met; RB-13 and RB-14 met through decisions and setup; RB-05, RB-12 and RB-18–20
closed during the first plan tasks.

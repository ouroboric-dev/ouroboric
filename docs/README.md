# Ouroboric

Ouroboric (ouroboric.dev) builds open factories that improve themselves: for software, companies,
and in time research and art. This repository is the company umbrella. Start with the
[charter](1-company/charter.md).

## The map

<!-- diagram: assets/diagrams/ouroboric-map.d2 -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/diagrams/rendered/ouroboric-map.dark.svg">
  <img alt="Ouroboric map: the founder approves direction in the Asgard realm (readiness checklist, kickstart graph later); Yggdrasil, the agentic factory, contains Odin, Jormungandr, Gleipnir, Havamal, Voluspa (the graph library, which gives Odin its graphs), the realms (Midgard and Helheim in v0, Jotunheim and Muspelheim later), the Asgard realm, and Ginnungagap (later), which creates realms, all honouring the Gungnir contract, with Ratatoskr, Norns, Mimir and Bragi later; the Asgard realm kickstarts and the other realms build companies and products, whose lessons and benchmarks feed back into Ouroboric" src="assets/diagrams/rendered/ouroboric-map.svg">
</picture>

The names come from Norse myth; the [naming and mythology record](7-branding/story/naming-and-mythology.md) tells the story behind each one, and its
[long-term map](7-branding/story/naming-and-mythology.md#glossary) shows what comes after v0.

## Contents

| Folder | What's there |
|---|---|
| [`1-company/`](1-company/charter.md) | charter, roadmap, legal, readiness |
| [`4-ways-of-working/`](4-ways-of-working/spec-driven-development.md) | the standards every Ouroboric product follows: [spec-driven development](4-ways-of-working/spec-driven-development.md), [docs](4-ways-of-working/docs-standard.md), [writing styles](4-ways-of-working/writing-styles.md), [diagrams](4-ways-of-working/diagrams.md) |
| [`5-research/`](5-research/README.md) | company-level research |
| [`6-journal/`](6-journal/README.md) | the journey: challenges, solutions, results |
| [`7-branding/`](7-branding/README.md) | the Ouroboric story, identity, voice, prompts |

Repositories in the `ouroboric-dev` organisation:

| Repository | Visibility | Role |
|---|---|---|
| `.github` | public | organisation profile and defaults (health files, issue forms, PR template); every change is organisation-wide |
| `ouroboric` | public | this company umbrella |
| `yggdrasil` | public | the product: the agentic factory |
| `asgard` | public | the Asgard realm; a product umbrella until it becomes a leaf of `yggdrasil` after Yggdrasil v0 |

Each operator also keeps a **private instance umbrella** (L0), outside this repository, with pinned
factory versions, their own projects, hidden benchmarks and private notes. It never lives here.

Products, as submodules under [`products/`](../products/) (clone with `--recurse-submodules`):

| Product | What it is |
|---|---|
| [Yggdrasil](https://github.com/ouroboric-dev/yggdrasil) | the agentic factory |
| [Asgard](https://github.com/ouroboric-dev/asgard) | Yggdrasil's kickstart realm; moves under `yggdrasil` after Yggdrasil v0 |

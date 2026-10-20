# Ouroboric

Ouroboric (ouroboric.dev) builds open factories that improve themselves: for software, companies,
and in time research and art. This repository is the company umbrella. Start with the
[charter](docs/1-company/charter.md).

## The map

<!-- diagram: assets/diagrams/ouroboric-map.d2 -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/diagrams/rendered/ouroboric-map.dark.svg">
  <img alt="Ouroboric map: the founder approves direction in the Asgard realm (readiness checklist, kickstart graph later); Yggdrasil, the agentic factory, contains Odin, Jormungandr, Gleipnir, Havamal, Voluspa (the graph library, which gives Odin its graphs), the realms (Midgard and Helheim in v0, Jotunheim and Muspelheim later), the Asgard realm, and Ginnungagap (later), which creates realms, all honouring the Gungnir contract, with Ratatoskr, Norns, Mimir and Bragi later; the Asgard realm kickstarts and the other realms build companies and products, whose lessons and benchmarks feed back into Ouroboric" src="docs/assets/diagrams/rendered/ouroboric-map.svg">
</picture>

The names come from Norse myth; the [naming and mythology record](docs/7-branding/story/naming-and-mythology.md) tells the story behind each one, and its
[long-term map](docs/7-branding/story/naming-and-mythology.md#glossary) shows what comes after v0.

## Contents

| Folder | What's there |
| --- | --- |
| [`1-company/`](docs/1-company/charter.md) | charter, roadmap, budget, legal, readiness, [repositories](docs/1-company/repos.md) |
| [`4-ways-of-working/`](docs/4-ways-of-working/spec-driven-development.md) | the standards every Ouroboric product follows: [spec-driven development](docs/4-ways-of-working/spec-driven-development.md), [docs](docs/4-ways-of-working/docs-standard.md), [writing styles](docs/4-ways-of-working/writing-styles.md), [diagrams](docs/4-ways-of-working/diagrams.md) |
| [`5-research/`](docs/5-research/README.md) | company-level research |
| [`6-journal/`](docs/6-journal/README.md) | the journey: challenges, solutions, results |
| [`7-branding/`](docs/7-branding/README.md) | the Ouroboric story, identity, voice, prompts |

The [repositories](docs/1-company/repos.md) page lists every repo in the `ouroboric-dev`
organisation and where it sits in the tree. The products are submodules under
[`products/`](products/): clone with `--recurse-submodules`.

## Contributing

Run `uvx pre-commit install` once after cloning, so `gitleaks` checks each commit for secrets.

## Licence

- **Documentation** (this repository's main content): [CC BY 4.0](LICENSE).
- **Scripts** (`scripts/`): [AGPL-3.0](LICENSES/AGPL-3.0-only.txt).
- **Names and logos** are not licensed: see [TRADEMARKS.md](TRADEMARKS.md).
- The products use AGPL-3.0 for factory code and MIT for anything copied into what operators build.
  **What you build with Ouroboric factories is yours.**

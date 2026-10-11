# Ouroboric

Ouroboric (ouroboric.dev) builds open factories that improve themselves: for software, companies,
and in time research and art. This repository is the company umbrella. Start with the
[charter](docs/1-company/charter.md).

## The map

<!-- diagram: assets/diagrams/ouroboric-map.d2 -->
![Ouroboric map: the operator approves direction in Asgard, the company factory (readiness checklist, Ginnungagap kickstart graph), which runs on Odin; Yggdrasil, the software factory, contains Odin, Jormungandr, Gleipnir, Havamal and the realms, all honouring the Gungnir contract, with Ratatoskr, Norns, Mimir and Bragi later; Asgard kickstarts and Yggdrasil builds companies and products, whose lessons and benchmarks feed back into Ouroboric](docs/assets/diagrams/rendered/ouroboric-map.svg)

The names come from Norse myth; the [naming and mythology record](docs/7-branding/story/naming-and-mythology.md) tells the story behind each one, and its
[long-term map](docs/7-branding/story/naming-and-mythology.md#glossary) shows what comes after v0.

## Contents

| Folder | What's there |
|---|---|
| [`1-company/`](docs/1-company/charter.md) | charter, roadmap, legal, readiness |
| [`4-ways-of-working/`](docs/4-ways-of-working/spec-driven-development.md) | the standards every Ouroboric product follows: [spec-driven development](docs/4-ways-of-working/spec-driven-development.md), [docs](docs/4-ways-of-working/docs-standard.md), [writing styles](docs/4-ways-of-working/writing-styles.md), [diagrams](docs/4-ways-of-working/diagrams.md) |
| [`5-research/`](docs/5-research/README.md) | company-level research |
| [`6-journal/`](docs/6-journal/README.md) | the journey: challenges, solutions, results |
| [`7-branding/`](docs/7-branding/README.md) | the Ouroboric story, identity, voice, prompts |

Repositories in the `ouroboric-dev` organisation:

| Repository | Visibility | Role |
|---|---|---|
| `.github` | public | organisation profile and defaults (health files, issue forms, PR template); every change is organisation-wide |
| `ouroboric` | public | this company umbrella |
| `yggdrasil`, `asgard` | public | the products |

Each operator also keeps a **private instance umbrella** (L0), outside this repository, with pinned
factory versions, their own projects, hidden benchmarks and private notes. It never lives here.

Products, as submodules under [`products/`](products/) (clone with `--recurse-submodules`):

| Product | What it is |
|---|---|
| [Yggdrasil](https://github.com/ouroboric-dev/yggdrasil) | the software factory |
| [Asgard](https://github.com/ouroboric-dev/asgard) | the company factory, running on Yggdrasil |

## Licence

- **Documentation** (this repository's main content): [CC BY 4.0](LICENSE).
- **Scripts** (`scripts/`): [AGPL-3.0](LICENSES/AGPL-3.0-only.txt).
- **Names and logos** are not licensed: see [TRADEMARKS.md](TRADEMARKS.md).
- The products use AGPL-3.0 for factory code and MIT for anything copied into what operators build.
  **What you build with Ouroboric factories is yours.**

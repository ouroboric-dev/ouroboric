---
title: Repositories
status: accepted
date: 2026-10-21
related: [../4-ways-of-working/docs-standard.md, charter.md]
style: reference
---

# Repositories

Every repository in the [`ouroboric-dev`](https://github.com/ouroboric-dev) organisation, what it is
and where it sits in the tree. Every public repo passes
[`scripts/check-repos.sh`](../../scripts/check-repos.sh) ([docs standard §9](../4-ways-of-working/docs-standard.md#9-repository-setup)).
This is a hand-kept list, not Yggdrasil's generated routing file `REPOS.md`.

## Umbrellas

| Repository | Kind | Role |
| --- | --- | --- |
| [`ouroboric`](https://github.com/ouroboric-dev/ouroboric) | company umbrella | this repo: charter, standards, journal, brand; the products as submodules under [`products/`](../../products/) |
| [`yggdrasil`](https://github.com/ouroboric-dev/yggdrasil) | product umbrella | the agentic factory; its leaves are submodules (below) |
| [`asgard`](https://github.com/ouroboric-dev/asgard) | product umbrella | the kickstart realm; becomes a leaf of `yggdrasil` after Yggdrasil v0 |

`yggdrasil` and `asgard` are the only repos with issues on.

## Yggdrasil's leaves

Submodules of `yggdrasil`, so they sit under `products/yggdrasil/` here.

| Repository | Role |
| --- | --- |
| [`gungnir`](https://github.com/ouroboric-dev/gungnir) | the contract: Go interface types and JSON schemas for ledger events, `graph.yaml`, `pack.yaml` and `factory.yaml` |
| [`odin`](https://github.com/ouroboric-dev/odin) | the orchestrator: the graph engine and the `ygg` CLI, with routing and the ledger as packages |
| [`gleipnir`](https://github.com/ouroboric-dev/gleipnir) | the harness: agent adapters, the devcontainer sandbox driver, policies and the check runner |
| [`jormungandr`](https://github.com/ouroboric-dev/jormungandr) | the loop: build, check and fix with attempts, backoff, budgets, feedback and escalation |
| [`havamal`](https://github.com/ouroboric-dev/havamal) | the skill library: vendored skills with `skills.lock` and licences, our own skills with their evals |
| [`voluspa`](https://github.com/ouroboric-dev/voluspa) | the graph library: one folder per graph, with its stage prompts |
| [`midgard-react`](https://github.com/ouroboric-dev/midgard-react) | the Midgard realm's React flavour: web frontends |
| [`helheim-go`](https://github.com/ouroboric-dev/helheim-go) | the Helheim realm's Go flavour: backends; holds the source of the realms' shared scripts |

## Other repos

Standalone repos, not submodules of any umbrella.

| Repository | Role |
| --- | --- |
| [`.github`](https://github.com/ouroboric-dev/.github) | the organisation profile and defaults (health files, issue forms, PR template); every change is organisation-wide |
| [`mimir`](https://github.com/ouroboric-dev/mimir) | the public benchmark kit: briefs, task format, sample suites and results |
| [`ouroboric-packages`](https://github.com/ouroboric-dev/ouroboric-packages) | the official `ouroboric` package on PyPI, which holds the name on the registry |

## Hidden repos

`huldra` holds the hidden benchmark suite. It is private, and the pr-bot is never installed on it, so
agents can't read it.

Each operator also keeps a **private instance umbrella** (L0), outside this organisation, with pinned
factory versions, their own projects, hidden benchmarks and private notes.

## Local clones

`check-repos.sh` expects the clones side by side in one folder: `ouroboric`, `yggdrasil` (with its
leaves inside), `asgard` and `mimir`. To get the products inside this repo instead, clone it with
`--recurse-submodules`.

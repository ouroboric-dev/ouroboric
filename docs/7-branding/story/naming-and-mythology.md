---
title: Naming and mythology
status: draft
date: 2026-10-11
related: [../prompts/nano-banana-logo-prompts.md]
style: brand-story
---

# Naming and mythology

Status: agreed 2026-10-11 (loop renamed to Jormungandr; Vitruvius replaced by Gungnir; Odin added as engine); the realms agreed 2026-10-17. This is the story behind the names. Use it for branding and for every
future naming decision, so new components fit the same world.

## The story

Yggdrasil is the world tree. Everything hangs on it: the nine realms in its branches, the wells
at its roots, the creatures that live on it.

The agentic factory is that tree. Every run climbs it from root to leaf. The nine **realms** hang
from its branches, one for each kind of work, and every product is built from leaves of one realm or
more (see [the realms](#the-realms)).

High in the tree sits **Asgard**, the realm of the gods, where direction and order are decided. Asgard
is the factory's **kickstart realm**: it sets charters, brands, legal ground and roadmaps for new
companies and products. Like the realm in the myth, it is one of the realms of Yggdrasil, and every
other realm builds on the direction it sets. Every new realm begins in **Ginnungagap**, the yawning
void before creation, where the worlds were shaped. Ginnungagap is the **realm that creates realms**,
and it stands outside the nine. The **repo tree** (umbrellas and leaves) is the tree's shape.

**Odin**, the All-Father, sits in his high seat and sees all nine worlds. He is the **orchestrator**:
the graph engine that directs the work and sends his ravens (the agents) out across the realms to
report back. His story carries a warning: at Ragnarok, Fenrir swallows Odin. An orchestrator that
relies on a power it fails to bind is undone by it. That is why the next part of the story matters.

The power that does the work is **Fenrir**, the great wolf: the model and the agents it drives. It
is useful and dangerous, and it can't be trusted unbound. The gods bound Fenrir with **Gleipnir**, a
ribbon thin as silk and stronger than any chain, made from impossible things. Gleipnir is the
**harness**: a light restraint on an enormous force, made of instructions, sandboxes, checks and
policies.

Around the middle world lies **Jormungandr**, the Midgard Serpent, biting its own tail. It is the
**loop**: build, check, fix, again, until the work holds or the limit is reached.

The Greeks called that shape the **Ouroboros**. It is the emblem above the whole tree and the brand
(`ouroboric-dev`): the factory that improves itself. The Ouroboros is a symbol, not a module.

**Ratatoskr**, the squirrel, runs up and down the trunk carrying messages between the eagle at the
crown and the serpent at the roots. It is **routing**: finding, one level at a time, where in the
tree the work belongs.

At the roots, the three **Norns** carve fate into the tree. Urd keeps what was, Verdandi what is,
and Skuld what shall be. They are **observability**: the ledger (past), live status (present), and
metrics, benchmarks and forecasts (future).

The deeds of the tree are kept as **sagas**: the journal of every challenge met, the solution tried,
and what came of it. One day **Bragi**, the god of poetry, will turn the sagas into stories for others
to read: the blog and the posts that share the journey.

Beside them is **Mimir's** well of wisdom. Odin gave an eye to drink from it, so its knowledge has
a real, measurable price. It is the **benchmarks**: what we learn about factories, and what learning
it costs.

**Heimdall** watches the **Bifrost**, the bridge from the tree to other worlds. Heimdall is the
**approval points**, and the Bifrost is the **integrations** that carry work outward: git remotes,
trackers, hosting and production.

Odin's wisdom is gathered in the **Havamal**, the Sayings of the High One: advice for living well,
ending with the list of charms Odin knows. Havamal is the **skill library**, and each skill is one of
Odin's charms: guidance an agent follows. A charm is only kept if it proves it works. Its sibling
poem, the **Voluspa** (the seeress's prophecy), tells the whole course of the world from creation to
the end. Voluspa is the **graph library**: the order that work follows. Havamal holds what agents
know, and Voluspa holds the order they work in.

A rule over all of it: **Gungnir**, Odin's spear. Oaths were sworn on its point, and it never
misses. Gungnir is the **component contract**, the interfaces and schemas every component must honour
to plug into the tree. A component "sworn on Gungnir" respects the contract, which is what makes
mix-and-match factories possible.

## The realms

**Decided 2026-10-17 (founder).** Each of the nine realms of the myth is one domain of work: the
answer to "what am I building?". A realm's **flavors** are the answer to "in what?". A realm leaf
(a repo) is named `<realm>-<flavor>` (`midgard-react`, `helheim-go`), or `<realm>` alone for a realm
with one way of working (`asgard`). A product that crosses domains is a combination of leaves: a web
SaaS is a Midgard leaf and a Helheim leaf, and a project may use several flavors of one realm.
Legacy and migration are kinds of work a realm may offer, not realms.

| Realm | Domain | Why the myth fits | Flavors (examples) |
| --- | --- | --- | --- |
| **Asgard** | kickstart: charters, brands, legal basics, roadmaps | where the gods decide direction | (one leaf: `asgard`) |
| **Midgard** | web frontends | the human world, the part people live in and see | `react`, `vue`, `next` |
| **Helheim** | backend: services, APIs, workers | below the world, behind the bridge Gjallarbru, where the guard Modgud asks every traveller their name and errand: the part no user sees, where every request is checked and every record is kept | `go` |
| **Niflheim** | infrastructure: deploy, cloud, operations | under one of Yggdrasil's roots, its well Hvergelmir feeds every river: the ground everything runs on | named with the realm |
| **Nidavellir** | desktop apps and command-line tools | the dwarves' realm; dwarves forged the gods' own tools (Mjolnir, Draupnir, Gungnir) | `tauri`, `cli` |
| **Jotunheim** | games (engine-based clients) | at Utgard the giants test Thor with contests: a race, an eating contest, wrestling old age itself | `godot`, `unity` |
| **Alfheim** | art: assets for apps and games (music, 3D models, sprites, icons), and later art as the work itself | the light elves' realm, "more beautiful than the sun" | `audio`, `3d`, `2d` |
| **Vanaheim** | research: documents from sources (a synthesis) or from data (a paper) | the Vanir, masters of seidr (seeing hidden things), whose truce with the gods produced Kvasir, who could answer any question | `synthesis`, `paper` |
| **Muspelheim** | mobile apps | the gods took sparks from Muspelheim and set them moving across the sky as the sun, moon and stars: lights that travel with you | `swift`, `kotlin`, `flutter` |

Naming a realm is not a commitment to build it. The roadmap says which realms come when. Muspelheim's
fit is the weakest of the nine. The flavor lists are examples: a flavor gets its name when its leaf is
created. The record of the decision is Yggdrasil's change proposal
[realm leaf naming](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/changes/2026-10-17-realm-leaf-naming/proposal.md).

**Decided 2026-10-18 (founder).** **Ginnungagap** is a realm outside the nine. Its domain is realms:
it creates realm leaves through `ygg run`, holds the realm readiness checklist, and is the source of
what every realm shares. Its leaf is `ginnungagap`. Graphs have descriptive names (`software`,
`kickstart`), not myth names: myth names are for realms and components. The record is Yggdrasil's
[Ginnungagap and Voluspa design doc](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/design/2026-10-18-ginnungagap-design.md).

## The adversaries

Naming the threats makes them easier to discuss in designs, docs and incident notes.

| Name | Myth | What it means here |
| --- | --- | --- |
| **Nidhogg** | the dragon gnawing at Yggdrasil's roots | entropy: AI slop, drift, technical debt. Cleanup and garbage-collection work fights Nidhogg |
| **Loki** | the trickster and shapeshifter who deceives the gods | prompt injection and deception: poisoned READMEs, malicious issues, hostile dependencies |
| **Ragnarok** | the end of the world, where everything falls together | the cascade: one bad change certified at every level, a leaked key reaching every repo, a bulk operation hitting every record |

## Glossary

The long-term picture: solid means v0, dashed means later, dotted means an optional name, and grey
means illustrative.

<!-- diagram: assets/diagrams/ouroboric-long-term-map.d2 -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../assets/diagrams/rendered/ouroboric-long-term-map.dark.svg">
  <img alt="Ouroboric long-term map: inside the company, the journal (sagas) feeds Bragi; Yggdrasil has its v0 core (Odin, Jormungandr, Gleipnir, Havamal, Gungnir, and Voluspa the graph library), the realms (Midgard and Helheim now; the Asgard kickstart realm, Ginnungagap the realm that creates realms, Jotunheim and Muspelheim later; Niflheim, Nidavellir, Alfheim and Vanaheim named, not committed), later modules (Ratatoskr, Norns, Mimir) and optional names (Heimdall, Bifrost); a future product factory is illustrative; Fenrir, the models and agents, is bound by Gleipnir; the adversaries are Loki, Nidhogg and Ragnarok" src="../../assets/diagrams/rendered/ouroboric-long-term-map.svg">
</picture>

| Name | Role | Status |
| --- | --- | --- |
| **Ouroboric** | the company: builds open, self-improving factories. The Ouroboros is its symbol | company |
| **Yggdrasil** (`ygg`) | the agentic factory, and its product umbrella repo. The CLI is `ygg` | v0 |
| **Asgard** | Yggdrasil's kickstart realm (tier 0): charters, brands, legal basics, roadmaps and readiness for companies and products. A company factory until 2026-10-17 | designed; v0 after Yggdrasil v0 |
| **Ginnungagap** | the realm that creates realms, outside the nine: the realm contract and readiness checklist, the pieces every realm shares, realm leaves made by `ygg run`. Until 2026-10-18 the name of Asgard's kickstart graph, now `kickstart` | designed; after Yggdrasil v0 |
| **Odin** | the orchestrator / graph engine: approval points, modes, checkpoints, tree topology, pointer propagation | v0 |
| **Gungnir** | the component contract: Go interface types and schemas (ledger events, graph.yaml, pack.yaml) | v0 |
| **Gleipnir** | harness layer: agent adapters, sandbox drivers, context assembly, policies, check runner | v0 |
| **Jormungandr** | loop layer: build→check→fix semantics, attempts, backoff, budgets, feedback, escalation | v0 |
| **Ouroboros** | the brand symbol and org (`ouroboric-dev`): self-improvement. Not a module | brand |
| **realms** | the nine domains of Yggdrasil's work, each with its flavors as leaf repos (`<realm>-<flavor>`): the stack layer, implementer prompt, templates and checks of the loop Odin runs (the graph lives in Voluspa). See [the realms](#the-realms) | v0 (Midgard and Helheim: `midgard-react`, `helheim-go`) |
| **Havamal** | the skill library: vendored and own skills, `skills.lock`, evals. Each skill is one of Odin's charms | v0 |
| **Voluspa** | the graph library: one graph for all software (`software`), later Asgard's `kickstart`. Runs pin it like a realm | built and name-screened (2026-10-19); `voluspa`, graph `software` |
| **Ratatoskr** | routing: per-umbrella index bundles, hierarchical descent | later as a module (v0 ships it as a package) |
| **Norns** | observability: ledger, metrics, reports, live status | later as a module |
| **Mimir** | benchmarks: kit, frozen briefs, hidden suites, scoring | later (its own milestone) |
| **Heimdall** | approval points, as a sub-component of Odin | optional name |
| **Bifrost** | integrations: Remote, Tracker, deploy targets | optional name |
| **Fenrir** | the model and agents themselves: the bound power | story only, not a module |
| **sagas** | journal entries: challenges, solutions, measured results (`docs/6-journal/`) | v0 (as documents) |
| **Bragi** | content: turns the sagas into blog posts and series | later |

Names not yet used, kept for later:

- **Huginn and Muninn:** Odin's ravens, thought and memory, who fly over the worlds and report back. Fit scout or research agents, or planner and memory roles.
- **Urd's well:** a persistent knowledge or state store.
- **Einherjar:** warriors who fall each day and rise each evening. Fits a retry/escalation sub-component of Jormungandr.
- **Draupnir:** Odin's ring that drips eight new rings every ninth night. Fits anything that yields an increment per cycle.

## Naming rules

1. **A component earns a name** only when it is a separately versioned module with its own
   interface. Until then it is a plain package name (`harness`, `loop`, `routing`).
2. **Use names from this world** (Norse myth for modules; the Ouroboros only as the brand symbol). A new
   name should have a myth that explains the component's job in one sentence.
3. **ASCII only** in code, CLIs, packages and repos: `Mimir`, not `Mímir`; `Bifrost`, not `Bifröst`;
   `Jormungandr`, not `Jörmungandr`.
4. **Check collisions before adopting a name.** "Yggdrasil" is a well-known Go mesh-network project
   and "Ouroboros" is Cardano's consensus protocol. "Odin" is also a programming language. The `github.com/ouroboric-dev/...` import path
   avoids technical conflicts, but searches will be noisy. The checks run on 2026-10-12 are in
   [name checks](../../5-research/2026-10-12-name-checks.md): only "Ouroboric" is free almost
   everywhere, so product and module names appear under the Ouroboric umbrella.
5. **The org is `ouroboric-dev`** (ouroboric.dev): the shared symbol of iteration, of factories
   improving themselves.
6. **A realm leaf is `<realm>-<flavor>`**, lowercase: one of the nine realms of
   [the realms](#the-realms), then the flavor (`midgard-react`). A realm with one way of working MAY
   be named `<realm>` alone (`asgard`). Realms are domains of work; a component is never named after
   a realm.

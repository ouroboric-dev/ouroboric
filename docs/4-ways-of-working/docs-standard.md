---
title: Documentation standard
status: accepted
date: 2026-10-12
related: [spec-driven-development.md]
---

# Documentation standard

**Ouroboric, its products, and every product they build** use one documentation template. The
factories document themselves the way they document what they make. Agents learn one map, and Odin's
routing and docs checks work the same everywhere.

## 1. Umbrella template

A node is one of three kinds: **company umbrellas** (for example, `ouroboric`, or a company that
the Asgard realm kickstarted), **product umbrellas** (for example, `yggdrasil`, a client gallery) and
**leaves**. Company
umbrellas use `1-company/` (charter, roadmap, legal, readiness) instead of `1-product/`, and hold the
standards their products inherit. Every umbrella otherwise uses this layout:

```
docs/
  README.md                landing page: what this is, and a map of the folders
  1-product/               DIRECTION (human-approved)
    charter.md             vision, mission, principles, north star, boundaries
    users.md, roadmap.md
    design/                design docs, dated
    legal/                 products: privacy, terms, data map, deletion process
  2-engineering/           HANDOVER AND BUILD
    system/                the living spec: how the system works today
    specs/                 specs (RFC-like), dated, not edited after acceptance
    changes/               change proposals with spec deltas
      archive/             merged proposals
    plans/                 implementation plans and tasks
  3-using/                 for users and operators (Diátaxis)
    tutorials/  how-to/  reference/  explanation/
    operations/            runbooks: install, upgrade, deploy, restore, rotate keys, incidents
  4-ways-of-working/       process: SDD, this standard, contributing, agent conventions
  5-research/              research briefs, curated sources
  6-journal/               challenges, solutions, measured results (the sagas)
  7-branding/              everything identity flows from
    story/                 naming, mythology, narrative
    identity/              palette, typography, design tokens: the design language
      logo/                logo, wordmark, favicon and app icons (trademark licence)
        concepts/          proposals and explorations kept for the record
    voice/                 tone, vocabulary, messaging pillars, copywriting rules
    prompts/               image-generation and copy prompts
  assets/
    diagrams/              diagram sources and their light and dark renders (see diagrams.md)
```

Raw sources that shouldn't be published, such as AI-generated rasters, stay out of the repo; only
final vectors and exports are committed.

The numeric prefixes order the rendered navigation. `3-using/` follows [Diátaxis](https://diataxis.fr/):
tutorials teach, how-to guides solve a task, reference describes, explanation gives the why.

## 2. Leaf template

```
README.md                  what the repo is, how to run it, where the docs are
AGENTS.md                  about 100 lines: a map into docs/, never a manual
docs/
  architecture.md          this repo's part of the system
  how-to/                  repo-specific tasks
  reference/               e.g. generated API docs from openapi.yaml
```

Direction, journal and branding live in the umbrella above the leaf.

## 3. Required and optional sections

| Section | Company umbrella | Product umbrella | Leaf |
|---|---|---|---|
| `README.md` | required | required | required |
| `1-company/charter.md`, `roadmap.md` | required | — | — |
| `1-company/readiness/` | required (readiness assessments, from the Asgard realm's checklist) | — | — |
| `1-company/legal/` | required before going public (licence, contribution terms, trademarks) | — | — |
| `1-product/charter.md`, `roadmap.md`, `design/` | — | required | — |
| `1-product/legal/` | — | optional while in development; **required before `deploy-prod`** | — |
| `2-engineering/*` | — | required | — |
| `3-using/` | — | required once there are users | `how-to/`, `reference/` |
| `3-using/operations/` | — | required before `deploy-prod` | — |
| `4-ways-of-working/` | required (the standards) | inherits from the company; may add rules | — |
| `5-research/` | optional | optional | — |
| `6-journal/` | required | optional (build in public) | — |
| `7-branding/` | required | optional (product sub-brand); required before a product's public launch if it has its own brand | — |
| `AGENTS.md`, `docs/architecture.md` | — | — | required |

Give each folder that has no content yet a short `README.md` that says what belongs there.

## 4. How products differ

- **`1-product/`** holds the product's charter (from the tier 0 kickstart), users and competitors.
- **`1-product/legal/`** holds the privacy policy, terms, **data map** (every place personal data
  lives: database rows, object storage originals and derivatives, zips, preview databases, backups)
  and the deletion process. A product that stores people's photos or emails handles personal data.
  Without a data map, a deletion request is guesswork, and a forgotten backup or preview branch can
  still hold the data. Reviewers raise a finding when a feature stores a new kind of personal data
  and doesn't update the data map.
- **`7-branding/` is an input to the build.** Implementers read `voice/` for interface copy and
  `identity/` for design tokens (the palette and type become the Tailwind theme).
- **The journal is optional.** When you learn a lesson about the factory on a private product, record
  it in the operator's private instance first. Only anonymised summaries reach the public factory
  journal.

## 5. Conventions

- **Front matter on every doc:**

  ```yaml
  ---
  title: <title>
  status: draft | accepted | implemented | superseded
  date: YYYY-MM-DD
  related: [relative links]
  style: <style id>            # optional; see writing-styles.md
  ---
  ```

  Journal entries use their own front matter (see `6-journal/README.md`).
- **File names:** dated for decisions and records (`YYYY-MM-DD-<slug>.md`: design docs, specs, change
  proposals, plans, journal); undated for living docs.
- **Decisions** inside any doc: `**Decided YYYY-MM-DD:** <decision>`.
- **Links:** relative within a repo; absolute URLs across repos.
- **Generated files** (`REPOS.md` wiring blocks, doc↔code, decisions indexes) say so at the top and
  have a `--check` mode that fails when they're stale.
- **Writing style:** every document has a style (legal, spec, procedure, marketing and others), set
  per section with overrides per folder or document. See [writing styles](writing-styles.md).
  Everywhere: short sentences, active voice, concrete examples, no undefined jargon.
- **Diagrams:** written as code (Mermaid, D2 and others) in `docs/assets/diagrams/`, rendered through a
  local Kroki. See [diagrams](diagrams.md).

## 6. Docs are checked like code

Every realm's check ladder has a docs rung. It checks:

- front matter present and valid;
- file naming and required sections per node type (§3);
- no broken links;
- prose rules for the document's style, checked by Vale ([writing styles §4](writing-styles.md#4-enforcement));
- a strict site build (once the renderer integration is in place).

As marola puts it, writing a doc is a deploy.

## 7. Rendering

- **Renderer: Zensical**, the successor to Material for MkDocs from the same
  team. It reads `mkdocs.yml`. Material for MkDocs is in maintenance mode, with security fixes only until
  about November 2026.
- **Stay renderer-agnostic:** plain Markdown, front matter, Mermaid, and the HTML `<picture>` element
  for light and dark images. Don't use renderer-specific syntax in the docs themselves. Then switching renderers means a new config file, not rewritten docs.
- **Aggregation:** each umbrella's site includes its children's docs at their pinned SHAs, recursively
  down the tree (marola's `prepare-docs.sh` pattern). The site shows what has actually been validated.
- **Known gaps:** Zensical doesn't yet have every Material plugin (redirects, blog, RSS, social cards).
  When the blog arrives, choose between Zensical's blog support (if it exists by then) and a separate
  site.

## 8. Public repos

The journal's scrubbing rules apply to every doc in a public repo: no secrets, no private product
names or code, no client data, no raw transcripts or ledger excerpts from private runs.

## 9. Repository setup

Every public `ouroboric-dev` repo must pass [`scripts/check-repos.sh`](../../scripts/check-repos.sh). It
checks:
- the repo settings: public, squash merges only, no wiki, and issues on for the factories
  (`yggdrasil`, `asgard`) and off for every other repo;
- secret scanning with push protection, and private vulnerability reporting;
- the `protect-main` ruleset;
- `reuse lint`;
- the `AGENTS.md` structure;
- the pinned `gitleaks` pre-commit hook;
- that the pr-bot can reach the repo.

Run one check with `--check <name>`, or name repos to check only those.

- **Hidden repos are the one exception.** `huldra` holds the hidden benchmark suite. It is private,
  and the pr-bot must never be installed on it, so agents can't read it. The pr-bot is installed on
  selected repos only, and `check-repos.sh`'s `bot` check fails if the pr-bot can reach a hidden
  repo.
- **The founder creates repos** with
  [`scripts/new-repo.sh --org <org> [--private] [--ci <piece>,...] <repo> "<description>"…`](../../scripts/new-repo.sh),
  using one token: fine-grained, short-lived, owned by the org, repository access "All
  repositories", with Administration, Contents and Workflows read and write. A real run confirmed
  this token on 2026-10-18; a token limited to selected repositories is untested. It runs every check
  first: if any named repo already exists, or a piece or the config is wrong, nothing is created.
  Each new repo gets a first commit with a `README.md`, whose first paragraph is the description,
  the licence files and the base CI, then the setup below, so agents only ever see a protected
  repo. If a step fails after a repo is created, the script names the repo and says it is not
  protected. Then the founder adds each public repo to the pr-bot's installation, as the script's
  output says. `--private` makes a hidden repo, which is never added. Another org copies
  [`scripts/orgs/ouroboric-dev.json`](../../scripts/orgs/ouroboric-dev.json) to
  `scripts/orgs/<org>.json` and changes the values ([the keys](../../scripts/orgs/README.md)).
- **Each step also runs alone**, with the same `--org`.
  [`create-repo.sh`](../../scripts/create-repo.sh) creates empty repos.
  [`add-licences.sh`](../../scripts/add-licences.sh) and [`add-ci.sh`](../../scripts/add-ci.sh)
  write the licence files and the base CI into a folder, and never overwrite a file. These three
  take `--check`, which runs every check and changes nothing.
  [`setup-repo.sh --org <org> <repo>`](../../scripts/setup-repo.sh) applies the setup below to
  an existing repo. It is safe to run twice and fixes drift, such as an extra ruleset rule.
  `create-repo.sh` and `setup-repo.sh` need the same token as `new-repo.sh`.
- **The base CI is pre-commit.** `add-ci.sh` writes `.pre-commit-config.yaml` from pinned pieces,
  and `.github/workflows/lint.yml`, which runs the hooks on every file and gitleaks over the
  history. `gitleaks` always runs. The config's `ci` list, or `--ci`, adds pieces: `reuse`,
  `markdown`, `shell`, `actions` and `yaml` ([the pieces](../../scripts/templates/ci/README.md)).
  The convention: `lint.yml` has the required job `lint`, and `ci.yml`, the repo's own tests, has
  the required job `test`. `setup-repo.sh` requires the check of each of these workflows that the
  repo has. The org's Actions allowlist must hold both of `lint.yml`'s actions, `actions/checkout`
  and `actions/setup-python`, at the SHAs it pins, or `lint` never starts; a pin bump updates the
  allowlist too.
- **Agents never create repos or change their settings.** They reach GitHub only as
  `ouroboric-pr-bot`, through [`scripts/as-bot.sh`](../../scripts/as-bot.sh), which can't; run the
  checks with `scripts/as-bot.sh --read all scripts/check-repos.sh`.
- **Agents scaffold a new Yggdrasil component** with
  [`scripts/scaffold-component.sh <repo> "<job>" <clone>`](../../scripts/scaffold-component.sh), in
  a clone of a new repo, on top of the first commit that `new-repo.sh` made. It adds the files
  from `scripts/templates/go-component/`, appends its sections to the README that commit holds,
  keeps the pre-commit config as it is, and leaves the architecture doc's responsibilities for a
  person to write. The result goes through a PR.
- **Reusable tooling lives here until it has a better home.** Any script that could run again goes
  in `scripts/`, with a test in `scripts/tests/`. When it should move, the Yggdrasil v0 plan's
  "Carried beyond v0" table says where and when. The repo scripts move into Yggdrasil's `github`
  remote, behind a hard approval point (change `2026-10-12-remote-creates-repos`), and the scaffold
  moves into Odin's `init`.

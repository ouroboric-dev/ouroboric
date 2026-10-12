---
title: Writing styles
status: accepted
date: 2026-10-12
related: [docs-standard.md, spec-driven-development.md]
---

# Writing styles

Different documents have different readers. Each document has one **style**, and each style has an
id. A style names the skills an agent loads when writing, the house rules that apply, and the checks
that run on the result. This standard applies to every Ouroboric product and to everything they build.

## 1. Which style applies

The most specific setting wins:

1. `style:` in the document's front matter;
2. a `style:` line in the nearest folder `README.md` (applies to everything beneath it);
3. the section default (§3);
4. the repository default: `guide`.

Styles apply per document, not per paragraph. When a document mixes kinds of text, the style
defines how to handle each block (for example, `spec` puts requirement sentences under STE rules).

## 2. The styles

Fourteen styles:

| Style id | Readers | Skills (vendored) | House rules |
|---|---|---|---|
| `direction` | decision-makers | `business-writing`, `plain-language` | bottom line first; one decision per paragraph; the charter's vision and mission lines follow `7-branding/voice/` once it exists |
| `spec` | engineers and agents | `google-dev-docs`, `asd-ste100` | prose follows Google developer style; **requirements and acceptance criteria follow ASD-STE100** (one meaning per sentence, approved vocabulary, at most 20 words); normative words follow RFC 2119 (MUST, SHOULD, MAY) |
| `guide` | operators and developers | `google-dev-docs` | structured by Diátaxis (tutorial, how-to, explanation); second person; tasks start with a verb |
| `procedure` | someone following steps, possibly under pressure | `asd-ste100` | numbered steps, one action each; warnings and cautions before the step they concern; no explanation inside steps |
| `reference` | someone looking something up | `google-dev-docs` | consistent tables and fields; mostly generated |
| `public-help` | a product's end users | `gov-uk-style`, `plain-language` | reading age about 9; front-load the answer |
| `legal` | users and regulators | `plain-language` | GDPR Article 12 requires privacy information "in a concise, transparent, intelligible and easily accessible form, using clear and plain language"; a qualified person reviews legal text before `deploy-prod` |
| `research` | future readers checking claims | `journalism-ap` | every claim attributed and cited; facts kept separate from analysis (marked `[ANALYSIS]`); unverified items marked |
| `journal` | readers of the journey | `orwells-rules` | concrete, honest, no jargon; include what went wrong |
| `brand-story` | everyone meeting the brand | `orwells-rules` + the house voice in `7-branding/voice/` | the mythic story told clearly, never decoratively |
| `marketing` | people deciding whether to read on | `scott-adams` + the house voice; **humanizer** pass | hook first; short sentences; no claim without evidence from the journal or ledger |
| `ui-copy` | a product's users, inside the interface | `plain-language` + the product's `7-branding/voice/` | short, consistent labels; error messages say what happened and what to do |
| `prompt` | generative models (image, video, music, text) | none; house rules only | concrete visual or sonic description; exact text in quotes and spelled out; aspect ratio and purpose stated; one asset per prompt; **never** a humanizer pass |
| `agent-facing` | models | `asd-ste100` | imperative; one instruction per sentence; a map, not a manual (point to docs instead of repeating them); **never** a humanizer pass |

### The humanizer pass

Humanizer removes tell-tale AI phrasing. It runs **last**, and only on text published for people:
`marketing`, public landing pages and blog posts. It never runs on `spec`, `procedure`, `reference`
or `agent-facing` text, where it would trade precision for natural-sounding prose.

## 3. Section defaults

| Path | Default style |
|---|---|
| `README.md` (repo and docs landing) | `guide` |
| `1-company/charter.md`, `roadmap.md`, `readiness/` | `direction` |
| `1-company/legal/` | `legal` |
| `1-product/charter.md`, `roadmap.md`, `design/` | `direction` |
| `1-product/users.md` | `direction` |
| `1-product/legal/` | `legal` |
| `2-engineering/` (all) | `spec` |
| `3-using/tutorials/`, `how-to/`, `explanation/` | `guide` |
| `3-using/reference/` | `reference` |
| `3-using/operations/` | `procedure` |
| `3-using/` in a product's end-user help centre | `public-help` |
| `4-ways-of-working/` | `guide` |
| `5-research/` | `research` |
| `6-journal/` | `journal` |
| `7-branding/story/` | `brand-story` |
| `7-branding/identity/` | `guide` |
| `7-branding/voice/` | `marketing` |
| `7-branding/prompts/` | `prompt` |
| `AGENTS.md`, realm prompts, skill files | `agent-facing` |
| interface text in product code | `ui-copy` |

## 4. Enforcement

- **When writing:** Gleipnir resolves the style by the rules in §1 and loads its skills **explicitly**
  into the agent's prompt. Gleipnir never leaves skills to trigger on their own.
- **When reviewing:** [Vale](https://vale.sh/) runs in the docs rung of every check ladder. Its
  configuration maps paths to rule sets that mirror §3 (for example, sentence-length and vocabulary
  limits for `procedure`, a readability floor for `legal`). Vale results become typed findings, like
  any other check.
- **Unknown style ids fail the docs check.**

## 5. Vendored skills

Every skill the factory uses is **vendored**: a pinned copy committed to the repository, never
whatever happens to be installed on a machine and never fetched live.

- **Why:** agents run in sandboxes that don't see the host's skills. Other operators have different
  skills or none. Benchmarks are only comparable with the same skills. And a skill is instructions that
  an agent follows with full permissions, so changes must arrive as reviewed diffs.
- **Where:** in **Havamal**, the skill library module, together with our own skills and their evals.
- **How:** a `skills.lock` (following marola's MIP-0080) records each skill's upstream repository,
  path, commit and licence, with a hash per file. A check fails when a vendored file differs from its
  lock entry. Updates arrive as pull requests whose diffs a human reviews. Every run's `run.json`
  records the skill set's hash.
- **Licences:** each vendored skill keeps its licence file. A skill whose licence doesn't allow
  redistribution can't be vendored, and so can't be part of the factory.
- **Sources:** vendor from the public upstream repository, never from a copy synced through an
  employer's or organisation's plugin system. Never vendor organisation-internal skills into a public
  repository.
- **Operator skills:** an operator may add private skills through their own L0 instance
  configuration. `run.json` records them, so benchmark results state which skills the run used.

| Skill | Upstream | Licence | Used by styles |
|---|---|---|---|
| `asd-ste100`, `business-writing`, `google-dev-docs`, `gov-uk-style`, `journalism-ap`, `orwells-rules`, `plain-language`, `scott-adams` | writing-skills (Surendran B), v0.6.0 | MIT | see §2 |
| humanizer | to be confirmed when vendored | to be checked when vendored | `marketing` pass |
| Ponytail (`ponytail-review`, `ponytail-audit`) | DietrichGebert/ponytail | MIT | reviewers ([spec-driven development §8](spec-driven-development.md#8-strategies-where-tools-plug-in)) |

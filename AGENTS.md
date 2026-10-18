# AGENTS.md: Ouroboric

Ouroboric is the company. This umbrella holds the company docs, the standards every product
inherits, and the products as submodules under `products/`. Start with `docs/README.md`.

## Invariants

These rules apply to every repo in this tree. A product's `AGENTS.md` may add rules; it must not
loosen these.

1. Humans steer. Stop and ask when work would leave an approved charter, spec or plan.
2. Write the failing test first. A test that never failed proves nothing.
3. Never merge a pull request, and never push to `main`. Humans merge.
4. Never read, print or store secrets, tokens or keys.
5. Never weaken a guardrail: approval points, sandbox settings, policies, rulesets or security tests.
6. Write each document in the style the docs standard assigns to its path.
7. Never commit raw sources that should not be published, such as AI-generated rasters or the
   founder's source images. Commit only final vectors and exports.
8. Work on a branch, stage files by path, and open a pull request for every change.

## Map

- Company direction: `docs/1-company/` (charter, roadmap, budget, legal, readiness).
- Standards: `docs/4-ways-of-working/` (spec-driven development, docs standard, writing styles,
  diagrams).
- Research and journal: `docs/5-research/`, `docs/6-journal/`.
- Brand: `docs/7-branding/` (story, identity, logo).

## Scripts

`scripts/` holds the tools of this tree. Before you run a GitHub, container-engine, plan or repo command by hand,
look here: a script exists for it, and the script is the deterministic way. Read the header of a script before
you run it. If you write a reusable script, it goes here with a test in `scripts/tests/`, never only in a scratch
folder.

| Need | Script |
|---|---|
| Push, open a pull request or read GitHub as `ouroboric-pr-bot` | `scripts/as-bot.sh <repo> <cmd>`; `--read all` to read. The only way an agent reaches GitHub |
| Any real-engine run (Podman, devcontainer, the sandbox): the engine, registry config and checks | `scripts/ygg-engine.sh check\|env\|run --folder DIR`. Never set `CONTAINER_HOST` by hand: the root socket is the wrong one |
| The realms smoke runs (v0-H13, v0-H15) and their evidence | `scripts/ygg-smoke-realms.sh`, `scripts/ygg-smoke-loop.sh`, `scripts/ygg-evidence.sh` |
| Build a plan from reference commits, or execute one task by task | `scripts/plan-*` (`plan-generate.py`, `plan-replay.py`, `plan-states.sh`, `plan-red.sh`, `plan-defences.py`; `plan-blocks.py`, `plan-task-start.sh`, `plan-task-done.sh`, `plan-task-land.sh`) |
| Check that the repos have the required setup | `scripts/as-bot.sh --read all scripts/check-repos.sh` |
| Scan git history for secrets | `scripts/scan-history.sh` |
| Create a repo with its first commit (`README.md`, licences, base CI) and its protection | `scripts/new-repo.sh --org <org> <repo> "<description>"`. Founder only |
| Write the licence files or the base CI into a folder | `scripts/add-licences.sh`, `scripts/add-ci.sh`. Founder only |
| Scaffold a new Go component | `scripts/scaffold-component.sh` |
| Render and check diagrams | `scripts/diagrams.sh` |

Only the founder runs `scripts/new-repo.sh`, `scripts/create-repo.sh`, `scripts/add-licences.sh`, `scripts/add-ci.sh`,
`scripts/setup-repo.sh` and `scripts/create-pr-bot.sh`.

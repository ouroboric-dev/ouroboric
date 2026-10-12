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
- Repo checks: `scripts/check-repos.sh`. Only the founder runs `scripts/setup-repo.sh`.
